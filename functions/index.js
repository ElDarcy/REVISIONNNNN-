/**
 * DORMANT SOURCE — NOT DEPLOYED.
 *
 * These Cloud Functions are intentionally NOT deployed: the Firebase project
 * `laundrycaps2` is on the free Spark plan, which does not support Cloud
 * Functions (they require the paid Blaze plan). Deployment is blocked.
 *
 * The core laundry workflow does NOT depend on any of these functions:
 *   - Order scheduling/processing is driven entirely client-side by
 *     OrderSchedulingGate (lib/engines/order_scheduling_gate.dart).
 *   - Pickup auto-assignment no longer relies on the `autoAssignPickupTask` /
 *     `autoAssignDeliveryQueueEntry` triggers. The Admin Flutter Web app is the
 *     primary reconciler (PickupReconciliationService + reconcilePendingPickups)
 *     and the Delivery Staff app is a secondary safety net; the assignment is
 *     performed inside a Firestore transaction for idempotency.
 *
 * These functions are kept as dormant source because the app UI still
 * references them for features that are currently non-functional in production:
 *   - publicTrack             → receipt QR tracking URL (lib/services/receipt_service.dart)
 *   - redeemPromotionRequest  → promo redemption requests (lib/services/engagement_customer_service.dart)
 *   - redeemLoyaltyRewardRequest → loyalty reward redemption requests (same)
 *   - repriceVerifiedOrder    → authoritative discount/weight reprice (lib/models/order_model.dart)
 *   - monitorMembershipExpirations / awardLoyaltyOnCompletion /
 *     reverseLoyaltyOnCancellation / monitorLaundryCycles → membership & loyalty
 *     maintenance and machine-cycle monitoring.
 *
 * Do NOT delete or modify these implementations unless the features above are
 * explicitly audited and restored/deployed (Blaze upgrade) or replaced.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

const ACTIVE_ORDER_STATUSES = new Set(['Completed', 'Delivered', 'Cancelled', 'Rejected']);
const ACTIVE_DELIVERY_STATUSES = new Set([
    'Pending Pickup', 'Pickup Assigned', 'Pending Delivery', 'Assigned', 'Out for Delivery',
]);

function isCashMethod(method) {
    return method === 'Cash on Pickup' || method === 'Cash at Shop' || method === 'Cash on Drop off';
}

// Pickup orders are NOT ready for a laundry worker until their laundry is
// physically at the shop, and cash pickup orders only after the collected cash
// has been remitted and confirmed by the admin (strict cash handover gate).
// Drop-off cash orders get a counter worker on 'Pending Collection' so they can
// collect the cash at the counter; they proceed on 'Verified' without waiting
// on remittance.
function laundryAssignmentReady(order) {
    const isPickup = order.deliveryMethod === 'Pickup';
    const cash = isCashMethod(order.paymentMethod);
    if (isPickup) {
        if (order.pickupStatus !== 'Laundry Collected') return false;
        if (cash && order.remittanceStatus !== 'Remitted') return false;
        return order.paymentStatus === 'Verified';
    }
    if (order.paymentStatus === 'Verified') return true;
    return cash && order.paymentStatus === 'Pending Collection';
}

// Payment verification is a server-side business transition.  The selected
// laundry worker is deterministic: lowest active workload, then longest idle,
// then lowest uid.  A transaction preserves an emergency manual reassignment.
exports.autoAssignLaundryAfterPayment = functions.firestore
    .document('orders/{orderId}')
    .onWrite(async (change, context) => {
        if (!change.after.exists) return null;
        const order = change.after.data();
        if (!laundryAssignmentReady(order) || hasLaundryStaff(order)) return null;

        const [usersSnap, ordersSnap] = await Promise.all([
            db.collection('users').get(),
            db.collection('orders').get(),
        ]);
        const staffIds = usersSnap.docs
            .filter(doc => ['staff', 'laundry_staff'].includes(doc.data().role) && doc.data().isActive !== false)
            .map(doc => doc.id);
        const selected = selectStaff(staffIds, ordersSnap.docs.map(doc => ({ id: doc.id, ...doc.data() })), 'laundry');
        if (!selected) return null;

        const assigned = await db.runTransaction(async transaction => {
            const latest = await transaction.get(change.after.ref);
            if (!latest.exists || !laundryAssignmentReady(latest.data()) || hasLaundryStaff(latest.data())) return false;
            transaction.update(change.after.ref, {
                assignedTo: selected,
                assignedStaffId: selected,
                staffId: selected,
                laundryStaffAssignmentSource: 'automatic',
                laundryStaffAssignedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return true;
        });
        if (assigned) {
            await deliverNotification(selected, 'Laundry task assigned', `You were automatically assigned transaction ${context.params.orderId.substring(0, 6).toUpperCase()}.`, 'operational', context.params.orderId);
        }
        return null;
    });

// Pickup orders need a delivery worker for the pickup leg.  Creating the queue
// entry here (server-side) guarantees it happens even when the client app
// lacks permission to read the staff roster; the deliveryQueue onCreate
// trigger then assigns the least-loaded delivery worker.
exports.autoAssignPickupTask = functions.firestore
    .document('orders/{orderId}')
    .onWrite(async (change, context) => {
        if (!change.after.exists) return null;
        const order = change.after.data();
        if (order.deliveryMethod !== 'Pickup') return null;
        if (order.pickupStatus === 'Laundry Collected') return null;

        const queueRef = db.collection('deliveryQueue').doc(`${context.params.orderId}__pickup`);
        const existing = await queueRef.get();
        if (existing.exists) return null;

        await queueRef.set({
            orderId: context.params.orderId,
            customerId: order.userId || order.customerId || null,
            customerName: order.customerName || null,
            type: 'pickup',
            address: extractAddress(order.deliveryAddress),
            latitude: Number(order.customerLatitude || 0),
            longitude: Number(order.customerLongitude || 0),
            distanceKm: Number(order.distanceKm || 0),
            priorityScore: 50,
            status: 'Pending Pickup',
            assignedTo: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return null;
    });

function extractAddress(address) {
    if (!address) return null;
    if (typeof address === 'string') return address;
    if (typeof address === 'object') return address.fullAddress || address.street || null;
    return null;
}

// Every pickup or delivery queue entry gets one delivery worker.  Queue docs
// use orderId as their ID (with a `__pickup` suffix for pickup-leg entries),
// so this also covers customer requests and the deadline job without ever
// duplicating a task.  Pickup entries carry their own orderId field, so the
// real order id is derived from that when the doc id is suffixed.
function realOrderIdFromQueueDoc(docId, data) {
    if (typeof docId === 'string' && docId.endsWith('__pickup')) {
        return docId.slice(0, -'__pickup'.length);
    }
    const stored = (data && data.orderId) || '';
    return typeof stored === 'string' && stored.length ? stored : docId;
}

exports.autoAssignDeliveryQueueEntry = functions.firestore
    .document('deliveryQueue/{orderId}')
    .onCreate(async (snapshot, context) => {
        if ((snapshot.data().assignedTo || '').toString()) return null;
        const orderId = realOrderIdFromQueueDoc(context.params.orderId, snapshot.data());
        const [usersSnap, queueSnap] = await Promise.all([
            db.collection('users').get(),
            db.collection('deliveryQueue').get(),
        ]);
        const staffIds = usersSnap.docs
            .filter(doc => doc.data().role === 'delivery_staff' && doc.data().isActive !== false)
            .map(doc => doc.id);
        const selected = selectStaff(staffIds, queueSnap.docs.map(doc => ({ id: doc.id, ...doc.data() })), 'delivery');
        if (!selected) return null;
        const assigned = await db.runTransaction(async transaction => {
            const queue = await transaction.get(snapshot.ref);
            if (!queue.exists || (queue.data().assignedTo || '').toString()) return false;
            transaction.update(snapshot.ref, {
                assignedTo: selected,
                assignmentSource: 'automatic',
                assignedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            transaction.set(db.collection('orders').doc(orderId), {
                assignedDeliveryStaffId: selected,
                deliveryStaffAssignmentSource: 'automatic',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return true;
        });
        if (assigned) {
            await deliverNotification(selected, 'Delivery task assigned', `You were automatically assigned transaction ${orderId.substring(0, 6).toUpperCase()}.`, 'operational', orderId);
        }
        return null;
    });

function hasLaundryStaff(order) {
    const id = order.assignedTo || order.staffId;
    return typeof id === 'string' && id.length > 0;
}

function toDate(value) {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate();
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function selectStaff(staffIds, records, kind) {
    if (!staffIds.length) return null;
    const workload = new Map();
    const lastActive = new Map();
    for (const record of records) {
        const id = kind === 'delivery' ? record.assignedTo : (record.assignedTo || record.staffId);
        if (!id) continue;
        const active = kind === 'delivery'
            ? ACTIVE_DELIVERY_STATUSES.has(record.status)
            : !ACTIVE_ORDER_STATUSES.has(record.status);
        if (active) workload.set(id, (workload.get(id) || 0) + 1);
        const activity = toDate(record.updatedAt || record.assignedAt || record.createdAt);
        if (activity && (!lastActive.has(id) || activity < lastActive.get(id))) lastActive.set(id, activity);
    }
    return staffIds.sort((a, b) => {
        const count = (workload.get(a) || 0) - (workload.get(b) || 0);
        if (count) return count;
        const aDate = lastActive.get(a), bDate = lastActive.get(b);
        if (!aDate && bDate) return -1;
        if (aDate && !bDate) return 1;
        if (aDate && bDate && aDate.getTime() !== bDate.getTime()) return aDate - bDate;
        return a.localeCompare(b);
    })[0];
}

/**
 * Public, read-only status endpoint for receipt QR codes. It intentionally
 * returns no user IDs, document IDs, addresses, payment data, or staff data.
 */
exports.publicTrack = functions.https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') return res.status(204).send('');
    const token = typeof req.query.token === 'string' ? req.query.token : '';
    if (!/^[A-Za-z0-9_-]{40,}$/.test(token)) return res.status(400).json({ error: 'Invalid tracking link.' });
    try {
        const orderSnap = await db.collection('orders')
            .where('publicTrackingToken', '==', token).limit(1).get();
        if (orderSnap.empty) return res.status(404).json({ error: 'Tracking link not found.' });
        const order = orderSnap.docs[0].data();
        const loadsSnap = await db.collection('orderLoads').where('orderId', '==', orderSnap.docs[0].id).get();
        const loads = loadsSnap.docs.map(doc => {
            const load = doc.data();
            const finish = load.status === 'Drying' ? load.dryEstimatedFinish : load.washEstimatedFinish;
            return {
                loadNumber: load.loadNumber || 1,
                weight: Number(load.weight || 0),
                serviceType: load.serviceType || 'Laundry Service',
                status: load.status || 'Pending',
                machine: (load.status === 'Washing' || load.status === 'Machine Assigned') ? (load.washerId || null) :
                    ((load.status === 'Drying' || load.status === 'Dryer Assigned') ? (load.dryerId || null) : null),
                estimatedFinish: finish && typeof finish.toDate === 'function' ? finish.toDate().toISOString() : null,
            };
        }).sort((a, b) => a.loadNumber - b.loadNumber);
        const payload = {
            transactionNumber: order.transactionNumber || 'Laundry Transaction',
            status: order.status || 'Pending',
            loadCount: loads.length || Number(order.numberOfLoads || 0),
            loads,
        };
        if (req.query.format === 'json' || (req.get('accept') || '').includes('application/json')) return res.json(payload);
        return res.type('html').send(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Track Laundry</title><style>body{font-family:Arial,sans-serif;background:#f5f7fa;margin:0;padding:24px;color:#172033}.card{max-width:480px;margin:auto;background:white;padding:24px;border-radius:14px;box-shadow:0 4px 18px #0002}h1{font-size:20px;margin:0 0 6px}.status{color:#1565c0;font-weight:bold}.load{border-top:1px solid #e5e7eb;padding:12px 0}.muted{color:#667085;font-size:14px}</style></head><body><main class="card"><h1>THIA & NICOLE Laundry Shop</h1><p class="muted">Sabalo St, Dagat-Dagatan, Caloocan City</p><h2>${payload.transactionNumber}</h2><p class="status">${payload.status}</p><div id="loads"></div></main><script>const d=${JSON.stringify(payload)};function render(x){document.getElementById('loads').innerHTML=x.loads.map(l=>'<div class="load"><b>Load '+l.loadNumber+'</b><br><span class="muted">'+l.weight.toFixed(1)+' kg • '+l.serviceType+'</span><br>'+l.status+(l.machine?' • '+l.machine:'')+(l.estimatedFinish?'<br><span class="muted">Estimated finish: '+new Date(l.estimatedFinish).toLocaleString()+'</span>':'')+'</div>').join('')}render(d);setInterval(async()=>{try{const r=await fetch(location.pathname+location.search+'&format=json');if(r.ok)render(await r.json())}catch(e){}},15000)</script></body></html>`);
    } catch (error) {
        console.error('publicTrack failed', error);
        return res.status(500).json({ error: 'Unable to load tracking status.' });
    }
});

/**
 * Scheduled function to monitor active laundry cycles.
 * Runs every 15 seconds to check for 20s warnings and completions.
 */
exports.monitorLaundryCycles = functions.pubsub.schedule('every 1 minutes').onRun(async (context) => {
    const now = admin.firestore.Timestamp.now().toDate();
    const loadsRef = db.collection('orderLoads');

    const washingSnap = await loadsRef.where('status', '==', 'Washing').get();
    for (const doc of washingSnap.docs) {
        await processLoad(doc, 'wash', now);
    }

    const dryingSnap = await loadsRef.where('status', '==', 'Drying').get();
    for (const doc of dryingSnap.docs) {
        await processLoad(doc, 'dry', now);
    }

    await enforcePickupDeadlines(now);
    return null;
});

async function enforcePickupDeadlines(now) {
    const readySnap = await db.collection('orders')
        .where('status', '==', 'Ready for Pickup')
        .get();

    for (const orderDoc of readySnap.docs) {
        const order = orderDoc.data();
        const deadline = readFirestoreDate(order.pickupDeadlineAt || order.deliveryDeadlineAt);
        const customerId = order.userId || order.customerId || null;

        if (!deadline) continue;

        const deadlineMs = deadline.getTime();
        const reminderWindowMs = 24 * 60 * 60 * 1000;
        const reminderSent = Boolean(order.pickupReminderSent);
        const terminalSent = Boolean(order.pickupDeadlineNotifiedAt);

        if (deadlineMs <= now.getTime()) {
            if (terminalSent) continue;
            await queuePickupDeadlineAsDelivery(orderDoc, order, now);
            continue;
        }

        if (!reminderSent && (deadlineMs - now.getTime()) <= reminderWindowMs) {
            if (customerId) {
                const reminderText = `Your laundry is still waiting for pickup. Please claim it before ${formatPickupDeadline(deadline)} to avoid automatic delivery.`;
                await deliverNotification(
                    customerId,
                    'Pickup reminder',
                    reminderText,
                    'pickup_reminder',
                    orderDoc.id,
                );
            }

            await orderDoc.ref.update({
                pickupReminderSent: true,
                pickupReminderSentAt: admin.firestore.Timestamp.fromDate(now),
            });
        }
    }
}

async function queuePickupDeadlineAsDelivery(orderDoc, order, now) {
    const orderId = orderDoc.id;
    const customerId = order.userId || order.customerId || null;
    const customerName = order.customerName || 'Customer';
    const requestRef = db.collection('deliveryRequests').doc(orderId);
    const requestSnap = await requestRef.get();
    const currentStatus = requestSnap.exists ? (requestSnap.data().status || '') : '';
    const isAlreadyQueued = ['requested', 'queued', 'assigned', 'out_for_delivery', 'pickup_deadline_expired'].includes(currentStatus);

    if (isAlreadyQueued) return;

    const queued = await db.runTransaction(async (transaction) => {
        const latestOrder = await transaction.get(orderDoc.ref);
        if (!latestOrder.exists || latestOrder.data().status !== 'Ready for Pickup') return false;
        const latestRequest = await transaction.get(requestRef);
        const latestStatus = latestRequest.exists ? (latestRequest.data().status || '') : '';
        if (['requested', 'queued', 'assigned', 'out_for_delivery', 'pickup_deadline_expired'].includes(latestStatus)) return false;

        const deadlineValue = latestOrder.data().pickupDeadlineAt || latestOrder.data().deliveryDeadlineAt || admin.firestore.Timestamp.fromDate(now);

        transaction.set(requestRef, {
            orderId,
            customerId: customerId || '',
            customerName,
            status: 'pickup_deadline_expired',
            source: 'pickup_timeout',
            requestedAt: latestOrder.data().deliveryRequestedAt || admin.firestore.Timestamp.fromDate(now),
            deadlineAt: deadlineValue,
            createdAt: admin.firestore.Timestamp.fromDate(now),
            updatedAt: admin.firestore.Timestamp.fromDate(now),
            deliveryFee: Number(latestOrder.data().deliveryFee || 0),
            paymentMethod: latestOrder.data().paymentMethod || 'GCash',
            paymentStatus: latestOrder.data().paymentStatus || 'Pending Verification',
            addressSnapshot: latestOrder.data().customerAddress || latestOrder.data().deliveryAddress || null,
            latitude: latestOrder.data().customerLatitude ?? null,
            longitude: latestOrder.data().customerLongitude ?? null,
            distanceKm: latestOrder.data().distanceKm ?? null,
        });

        transaction.update(orderDoc.ref, {
            deliveryRequestStatus: 'pickup_deadline_expired',
            deliveryRequestSource: 'pickup_timeout',
            deliveryRequestId: orderId,
            status: 'Ready for Delivery',
            pickupDeadlineNotifiedAt: admin.firestore.Timestamp.fromDate(now),
            updatedAt: admin.firestore.Timestamp.fromDate(now),
        });
        return true;
    });

    if (!queued) return;

    await db.collection('deliveryQueue').doc(orderId).set({
        orderId,
        customerId: customerId || '',
        customerName,
        address: getOrderAddress(order),
        latitude: Number(order.customerLatitude || 0),
        longitude: Number(order.customerLongitude || 0),
        distanceKm: Number(order.distanceKm || 0),
        priorityScore: 50,
        status: 'Pending Delivery',
        type: 'delivery',
        createdAt: admin.firestore.Timestamp.fromDate(now),
        updatedAt: admin.firestore.Timestamp.fromDate(now),
    }, { merge: true });

    if (customerId) {
        await deliverNotification(
            customerId,
            'Pickup deadline reached',
            'Your laundry was not claimed within 2 days, so it has been queued for delivery.',
            'pickup_deadline',
            orderId,
        );
    }
}

function readFirestoreDate(value) {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate();
    if (value instanceof Date) return value;
    if (typeof value === 'string') return new Date(value);
    return null;
}

function getOrderAddress(order) {
    if (order.deliveryAddress && typeof order.deliveryAddress === 'object') {
        return order.deliveryAddress.fullAddress || order.deliveryAddress.street || '';
    }
    return order.customerAddress || '';
}

function formatPickupDeadline(date) {
    return date.toLocaleString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
    });
}

async function processLoad(doc, type, now) {
    const data = doc.data();
    const loadId = doc.id;
    const orderId = data.orderId;
    const userId = data.userId;
    const loadNum = data.loadNumber;

    const finishField = type === 'wash' ? 'washEstimatedFinish' : 'dryEstimatedFinish';
    const warningSentField = type === 'wash' ? 'washWarningSent' : 'dryWarningSent';
    const completionSentField = type === 'wash' ? 'washCompletionSent' : 'dryCompletionSent';

    const finishTime = data[finishField] ? data[finishField].toDate() : null;
    if (!finishTime) return;

    const diffSeconds = (finishTime.getTime() - now.getTime()) / 1000;

    // 20-second warning
    if (diffSeconds <= 20 && diffSeconds > 0 && !data[warningSentField]) {
        await sendCycleNotification(doc, type, 'warning');
        await doc.ref.update({ [warningSentField]: true });
    }

    // Completion
    if (diffSeconds <= 0 && !data[completionSentField]) {
        await sendCycleNotification(doc, type, 'completed');
        await doc.ref.update({ [completionSentField]: true });
    }
}

async function sendCycleNotification(loadDoc, cycleType, eventType) {
    const data = loadDoc.data();
    const orderId = data.orderId;
    const loadNum = data.loadNumber;

    // 1. Get Parent Order for Customer Info
    const orderDoc = await db.collection('orders').doc(orderId).get();
    const customerId = orderDoc.exists ? orderDoc.data().userId : null;

    // 2. Notification Content
    let staffTitle, staffBody, customerTitle, customerBody;
    const machineId = cycleType === 'wash' ? data.washerId : data.dryerId;
    const typeLabel = cycleType === 'wash' ? 'washing' : 'drying';

    if (eventType === 'warning') {
        staffTitle = `🔔 Load #${loadNum} almost finished`;
        staffBody = `${machineId} (${typeLabel}) has about 20s remaining.`;

        customerTitle = `Almost Done!`;
        customerBody = `Your laundry Load #${loadNum} is almost finished ${typeLabel}.`;
    } else {
        staffTitle = `✅ Load #${loadNum} completed`;
        staffBody = `${machineId} cycle finished. Please check machine.`;

        customerTitle = `Cycle Completed`;
        customerBody = `Your laundry Load #${loadNum} has finished ${typeLabel}.`;
    }

    // 3. Send to ALL Staff
    const staffSnap = await db.collection('users').where('role', '==', 'staff').get();
    for (const staff of staffSnap.docs) {
        await deliverNotification(staff.id, staffTitle, staffBody, 'operational', orderId);
    }

    // 4. Send to Customer
    if (customerId) {
        await deliverNotification(customerId, customerTitle, customerBody, 'milestone', orderId);
    }
}

async function deliverNotification(userId, title, body, type, orderId) {
    // A. Persist in History
    await db.collection('notifications').add({
        userId, title, body, type, orderId,
        isRead: false,
        createdAt: admin.firestore.Timestamp.now()
    });

    // B. Send FCM Push
    const tokensSnap = await db.collection('users').doc(userId).collection('fcmTokens').get();
    const tokens = tokensSnap.docs.map(t => t.data().token);

    if (tokens.length > 0) {
        const message = {
            notification: { title, body },
            data: { orderId: orderId || '', type: type },
            tokens: tokens
        };
        await admin.messaging().sendMulticast(message);
    }
}

// ---- Customer engagement configuration ----------------------------------
// These functions only add benefits around the established order lifecycle.
// They never approve payment, infer actual weight, select a machine, or alter
// delivery fees. Firestore rules must restrict settings and verification writes
// to administrators.
function setting(data, name, fallback = true) { return data && data[name] !== undefined ? Boolean(data[name]) : fallback; }
function normalService(value) { return String(value || '').toLowerCase().replace(/[^a-z]/g, ''); }
function isActiveSubscription(data, now) {
    const expiry = readFirestoreDate(data.expiryDate);
    return data.status === 'Active' && data.paymentStatus === 'Verified' && expiry && now < expiry;
}
async function engagementContext(customerId, now) {
    const [settingsSnap, subsSnap] = await Promise.all([
        db.doc('system_settings/business_features').get(),
        db.collection('subscriptions').where('customerId', '==', customerId).where('status', '==', 'Active').get(),
    ]);
    const subscription = subsSnap.docs.map(d => ({ id: d.id, ...d.data() })).find(s => isActiveSubscription(s, now));
    const planSnap = subscription ? await db.collection('membership_plans').doc(subscription.planId).get() : null;
    return { features: settingsSnap.data() || {}, subscription, plan: planSnap && planSnap.exists ? planSnap.data() : null };
}

function promoDiscountFor(promo, subtotal) {
    const safeSubtotal = Number.isFinite(Number(subtotal)) ? Math.max(0, Number(subtotal)) : 0;
    const raw = promo.type === 'fixed' ? Number(promo.value || 0) : safeSubtotal * Number(promo.value || 0) / 100;
    const configuredCap = promo.maximumDiscount == null ? safeSubtotal : Number(promo.maximumDiscount);
    const cap = Number.isFinite(configuredCap) ? Math.max(0, Math.min(configuredCap, safeSubtotal)) : safeSubtotal;
    return Number.isFinite(raw) ? Math.max(0, Math.min(raw, cap)) : 0;
}

function promoEligibilityReason(promo, { now, subtotal, membershipActive, promoUsage = 0, customerPromoUsage = 0 }) {
    if (!promo || promo.status !== 'Active') return 'Promo inactive';
    if (!['fixed', 'percentage'].includes(promo.type)) return 'Invalid promo type';
    if (!Number.isFinite(Number(promo.value)) || Number(promo.value) <= 0) return 'Invalid promo value';
    if (!Number.isFinite(Number(subtotal)) || Number(subtotal) < Number(promo.minimumOrderAmount || 0)) return 'Minimum order not met';
    const start = readFirestoreDate(promo.startDate), end = readFirestoreDate(promo.endDate);
    if ((start && now < start) || (end && now > end)) return 'Promo unavailable';
    if (promo.memberOnly && !membershipActive) return 'Members only';
    if (promo.usageLimit != null && (!Number.isFinite(Number(promo.usageLimit)) || promoUsage >= Number(promo.usageLimit))) return 'Promo usage limit reached';
    if (promo.customerUsageLimit != null && (!Number.isFinite(Number(promo.customerUsageLimit)) || customerPromoUsage >= Number(promo.customerUsageLimit))) return 'Customer promo limit reached';
    return null;
}

// This is the final redemption point.  It deliberately runs after staff has
// verified actualWeight, so the existing load rule (ceil(weight / 8)) remains
// authoritative and a quote can never consume a promotion.
exports.repriceVerifiedOrder = functions.firestore.document('orders/{orderId}').onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const order = change.after.data();
    if (order.weightStatus !== 'verified' || !Number(order.actualWeight) || order.engagementPriceFinalized) return null;

    await db.runTransaction(async t => {
        const orderRef = change.after.ref;
        const latest = await t.get(orderRef);
        if (!latest.exists || latest.data().weightStatus !== 'verified' || !Number(latest.data().actualWeight) || latest.data().engagementPriceFinalized) return;
        const current = latest.data(); const customerId = current.userId || current.customerId;
        const serviceKey = normalService(current.serviceType || (current.items && current.items[0] && current.items[0].serviceName));
        const [settingsSnap, pricesSnap, subscriptionsSnap] = await Promise.all([
            t.get(db.doc('system_settings/business_features')),
            t.get(db.collection('service_pricing').where('status', '==', 'Active')),
            t.get(db.collection('subscriptions').where('customerId', '==', customerId).where('status', '==', 'Active')),
        ]);
        const priceDoc = pricesSnap.docs.find(d => normalService(d.data().name) === serviceKey || normalService(d.id) === serviceKey);
        if (!priceDoc) return; // Existing orders remain untouched until configured.
        const now = new Date(); const features = settingsSnap.data() || {};
        const subscriptionDoc = subscriptionsSnap.docs.find(d => isActiveSubscription(d.data(), now));
        const planRef = subscriptionDoc ? db.collection('membership_plans').doc(subscriptionDoc.data().planId) : null;
        const planSnap = planRef ? await t.get(planRef) : null;
        const membershipActive = setting(features, 'membershipEnabled') && subscriptionDoc && planSnap && planSnap.exists && planSnap.data().status === 'Active';
        const loads = Math.ceil(Number(current.actualWeight) / 8);
        const laundrySubtotal = loads * Number(priceDoc.data().pricePerLoad || 0);
        const eligibleMemberDiscount = membershipActive ? laundrySubtotal * Number(planSnap.data().discountPercent || 0) / 100 : 0;

        const code = String(current.requestedPromoCode || '').trim().toUpperCase();
        let eligiblePromoDiscount = 0; let promoReason = null; let promoRef = null; let promo = null;
        let usageRef = null; let customerUsageRef = null; let priorRedemption = null; let redemptionRef = null;
        let promoUsage = 0; let customerPromoUsage = 0;
        if (code) {
            const promoQuery = await t.get(db.collection('promotions').where('code', '==', code).limit(1));
            if (promoQuery.empty) promoReason = 'Promo not found';
            else {
                promoRef = promoQuery.docs[0].ref; promo = promoQuery.docs[0].data();
                usageRef = db.collection('promotion_usage').doc(promoRef.id);
                customerUsageRef = usageRef.collection('customers').doc(customerId);
                redemptionRef = db.collection('promotion_redemptions').doc(context.params.orderId);
                const [usageSnap, customerUsageSnap, redemptionSnap] = await Promise.all([t.get(usageRef), t.get(customerUsageRef), t.get(redemptionRef)]);
                priorRedemption = redemptionSnap;
                promoUsage = Math.max(Number(promo.usageCount || 0), Number(usageSnap.exists ? usageSnap.data().count : 0));
                customerPromoUsage = Number(customerUsageSnap.exists ? customerUsageSnap.data().count : 0);
                if (!setting(features, 'promotionsEnabled')) promoReason = 'Promotions disabled';
                else {
                    promoReason = promoEligibilityReason(promo, { now, subtotal: laundrySubtotal, membershipActive, promoUsage, customerPromoUsage });
                    if (!promoReason) eligiblePromoDiscount = promoDiscountFor(promo, laundrySubtotal);
                }

                // An event retry finds this immutable order-id redemption and
                // must neither increment counters nor create another record.
                if (priorRedemption.exists) eligiblePromoDiscount = Number(priorRedemption.data().discount || 0);
            }
        }
        const stackingAllowed = features.allowDiscountStacking === true;
        const usePromo = eligiblePromoDiscount > 0 && (stackingAllowed || eligiblePromoDiscount > eligibleMemberDiscount);
        const membershipDiscount = stackingAllowed || !usePromo ? eligibleMemberDiscount : 0;
        const promoDiscount = usePromo ? eligiblePromoDiscount : 0;
        if (usePromo && redemptionRef && !priorRedemption.exists) {
            t.set(redemptionRef, { orderId: context.params.orderId, customerId, promoId: promoRef.id, code, discount: promoDiscount, laundrySubtotal, createdAt: admin.firestore.FieldValue.serverTimestamp() });
            t.set(usageRef, { count: promoUsage + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
            t.set(customerUsageRef, { customerId, count: customerPromoUsage + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
            t.update(promoRef, { usageCount: promoUsage + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
        }
const deliveryFee = Math.max(0, Number(current.deliveryFee || 0)); // produced by DeliveryFeeEngine at order creation
        const soapTotal = Number(current.soapTotal || 0);
        const total = laundrySubtotal - membershipDiscount - promoDiscount + deliveryFee + soapTotal;
        // Balance reconciliation: finalAmount is the authoritative price after
        // verified weight. amountPaid is whatever the customer has actually paid
        // (set by payment verification and by balance collections). The order is
        // never "fully paid" while a positive balance remains unsettled.
        const amountPaid = Math.max(0, Number(current.amountPaid || 0));
        const balanceDue = Math.max(0, total - amountPaid);
        const refundAmount = Math.max(0, amountPaid - total);
        t.update(orderRef, {
            numberOfLoads: loads, subtotal: laundrySubtotal, laundrySubtotal,
            membershipDiscount, promoDiscount,
            finalAmount: total,
            balanceDue, refundAmount,
            pricingBreakdown: { loadCount: loads, laundrySubtotal, membershipDiscount, promoDiscount, appliedDiscount: membershipDiscount + promoDiscount, deliveryFee, total },
            totalAmount: total, engagementPriceFinalized: true,
            engagementPricedAt: admin.firestore.FieldValue.serverTimestamp(),
            promoFinalizationStatus: code ? (promoDiscount > 0 ? 'Redeemed' : 'Rejected') : 'Not requested',
            promoFinalizationReason: code && promoDiscount === 0 ? (promoReason || 'A better membership discount applies') : null,
        });
    });
    return null;
});

// Completion may be observed more than once. The order id is the immutable
// loyalty transaction id, making point issuance exactly-once.
exports.awardLoyaltyOnCompletion = functions.firestore.document('orders/{orderId}').onWrite(async (change, context) => {
    if (!change.after.exists || change.after.data().status !== 'Completed' || (change.before.exists && change.before.data().status === 'Completed')) return null;
    const order = change.after.data(); const now = new Date(); const ctx = await engagementContext(order.userId || order.customerId, now);
    if (!setting(ctx.features, 'loyaltyEnabled')) return null;
    const spend = Number(order.laundrySubtotal ?? order.subtotal ?? 0);
    // Read configurable rates from loyalty_settings instead of hardcoding
    let spendAmount = 100, pointsAwarded = 10;
    try { const ls = await db.doc('loyalty_settings/default').get(); if (ls.exists) { spendAmount = Number(ls.data().spendAmount || 100); pointsAwarded = Number(ls.data().pointsAwarded || 10); } } catch(e) {}
    if (spendAmount <= 0) spendAmount = 100;
    if (pointsAwarded <= 0) pointsAwarded = 10;
    let points = Math.floor(spend / spendAmount) * pointsAwarded;
    if (ctx.subscription && ctx.plan) points = Math.floor(points * Number(ctx.plan.loyaltyMultiplier || 1));
    if (!points) return null;
    const txRef = db.collection('loyalty_transactions').doc(context.params.orderId);
    const balanceRef = db.collection('loyalty_balances').doc(order.userId || order.customerId);
    await db.runTransaction(async t => {
        if ((await t.get(txRef)).exists) return;
        const balance = await t.get(balanceRef); const current = balance.exists ? Number(balance.data().points || 0) : 0;
        t.set(txRef, { orderId: context.params.orderId, customerId: order.userId || order.customerId, points, type: 'earn', createdAt: admin.firestore.FieldValue.serverTimestamp() });
        t.set(balanceRef, { customerId: order.userId || order.customerId, points: current + points, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }); return null;
});

exports.applyMembershipQueuePriority = functions.firestore.document('orders/{orderId}').onWrite(async (change, context) => {
    if (!change.after.exists || change.after.data().paymentStatus !== 'Verified' || (change.before.exists && change.before.data().paymentStatus === 'Verified')) return null;
    const order = change.after.data(); const ctx = await engagementContext(order.userId || order.customerId, new Date());
    if (!setting(ctx.features, 'prioritySchedulingEnabled') || !ctx.subscription || !ctx.plan || !ctx.plan.prioritySchedulingEnabled) return null;
    // Queue ordering only: no machine is assigned or made available here.
    return db.collection('deliveryQueue').doc(context.params.orderId).set({ priorityScore: 100, membershipPriority: true, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
});

async function engagementNotificationOnce(key, userId, title, body, subscriptionId) {
    const ref = db.collection('notifications').doc(key);
    await db.runTransaction(async t => { if ((await t.get(ref)).exists) return; t.set(ref, { userId, title, body, type: 'membership_expiry', subscriptionId, isRead: false, createdAt: admin.firestore.FieldValue.serverTimestamp() }); });
}
exports.monitorMembershipExpirations = functions.pubsub.schedule('every 24 hours').onRun(async () => {
    const now = new Date(); const subs = await db.collection('subscriptions').where('status', 'in', ['Pending', 'Active']).get();
    for (const doc of subs.docs) { const s = doc.data(); const expiry = readFirestoreDate(s.expiryDate); if (!expiry) continue; const days = Math.ceil((expiry - now) / 86400000); const user = s.customerId;
        if (expiry <= now) { await doc.ref.set({ status: 'Expired', expiredAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true }); await engagementNotificationOnce(`${doc.id}_expired`, user, 'Membership expired', 'Your Premium Laundry Membership has expired.', doc.id); }
        else if ([7, 3, 1].includes(days)) await engagementNotificationOnce(`${doc.id}_${days}_day_expiry`, user, 'Membership expiring soon', `Your Premium Laundry Membership expires in ${days} day${days === 1 ? '' : 's'}.`, doc.id);
    } return null;
});

// Customer apps submit only a code/order reference; the server computes and
// commits every discount under a transaction. A deterministic request id makes
// retries harmless and prevents the client from selecting a discount amount.
exports.redeemPromotionRequest = functions.firestore.document('promo_redemption_requests/{requestId}').onCreate(async (snap, context) => {
    const request = snap.data(); const customerId = request.customerId; const code = String(request.code || '').trim().toUpperCase();
    if (!customerId || !code) return snap.ref.set({ status: 'Rejected', reason: 'Invalid request' }, { merge: true });
    const promoSnap = await db.collection('promotions').where('code', '==', code).limit(1).get();
    if (promoSnap.empty) return snap.ref.set({ status: 'Rejected', reason: 'Promo not found' }, { merge: true });
    const promoRef = promoSnap.docs[0].ref;
    const now = new Date();
    await db.runTransaction(async t => {
        const [settings, promoDoc] = await Promise.all([t.get(db.doc('system_settings/business_features')), t.get(promoRef)]);
        const p = promoDoc.data(); if (!setting(settings.data(), 'promotionsEnabled')) throw Error('Promotions disabled');
        if (!p || p.status !== 'Active') throw Error('Promo inactive');
        const start = readFirestoreDate(p.startDate), end = readFirestoreDate(p.endDate);
        if ((start && now < start) || (end && now > end)) throw Error('Promo unavailable');
        const orderRef = request.orderId ? db.collection('orders').doc(request.orderId) : null; const order = orderRef ? await t.get(orderRef) : null;
        const subtotal = order && order.exists ? Number(order.data().laundrySubtotal || order.data().subtotal || 0) : Number(request.laundrySubtotal || 0);
        if (subtotal < Number(p.minimumOrderAmount || 0)) throw Error('Minimum order not met');
        const ctx = await engagementContext(customerId, now);
        const membershipActive = setting(ctx.features, 'membershipEnabled') && ctx.subscription && ctx.plan && ctx.plan.status === 'Active';
        const usageRef = db.collection('promotion_usage').doc(promoRef.id);
        const customerUsageRef = usageRef.collection('customers').doc(customerId);
        const [usageSnap, customerUsageSnap] = await Promise.all([t.get(usageRef), t.get(customerUsageRef)]);
        const promoUsage = Math.max(Number(p.usageCount || 0), Number(usageSnap.exists ? usageSnap.data().count : 0));
        const customerPromoUsage = Number(customerUsageSnap.exists ? customerUsageSnap.data().count : 0);
        const reason = promoEligibilityReason(p, { now, subtotal, membershipActive, promoUsage, customerPromoUsage });
        if (reason) throw Error(reason);
        // Checkout is a quote only. Usage is committed later with a concrete
        // order id, so abandoned checkout never consumes a limited promo.
        const discount = promoDiscountFor(p, subtotal);
        t.set(snap.ref, { status: 'Quoted', promoId: promoRef.id, code, discount, quotedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }).catch(async error => snap.ref.set({ status: 'Rejected', reason: error.message }, { merge: true })); return null;
});

exports.redeemLoyaltyRewardRequest = functions.firestore.document('loyalty_redemption_requests/{requestId}').onCreate(async snap => {
    const r = snap.data(), customerId = r.customerId, rewardId = r.rewardId; if (!customerId || !rewardId) return null;
    const redemption = db.collection('loyalty_redemptions').doc(`${customerId}_${snap.id}`);
    await db.runTransaction(async t => {
        const [settings, reward, balance, prior] = await Promise.all([t.get(db.doc('system_settings/business_features')), t.get(db.collection('loyalty_rewards').doc(rewardId)), t.get(db.collection('loyalty_balances').doc(customerId)), t.get(redemption)]);
        if (!setting(settings.data(), 'loyaltyEnabled') || !setting(settings.data(), 'loyaltyRedemptionEnabled')) throw Error('Redemption unavailable');
        if (!reward.exists || reward.data().status !== 'Active') throw Error('Reward unavailable'); if (prior.exists) return;
        const rd = reward.data();
        const required = Number(rd.requiredPoints || 0), points = balance.exists ? Number(balance.data().points || 0) : 0; if (points < required) throw Error('Insufficient points');
        t.set(redemption, { customerId, rewardId, requiredPoints: required, rewardSnapshot: rd, createdAt: admin.firestore.FieldValue.serverTimestamp() });
        t.set(balance.ref, { customerId, points: points - required, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        // Fulfillment: generate a promo code for the reward value
        const rewardType = rd.type || 'fixed_discount';
        const rewardValue = Number(rd.value || 0);
        if (rewardType === 'fixed_discount' && rewardValue > 0) {
            const code = `LOYALTY-${snap.id.substring(0, 8).toUpperCase()}`;
            const now = new Date();
            const expiry = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000); // 30 days
            await db.collection('promotions').doc(code.toLowerCase()).set({
                code, name: `Loyalty: ${rd.name || 'Discount'}`, type: 'fixed', value: rewardValue,
                minimumOrderAmount: 0, status: 'Active', memberOnly: false,
                startDate: admin.firestore.Timestamp.fromDate(now),
                endDate: admin.firestore.Timestamp.fromDate(expiry),
                customerUsageLimit: 1, usageLimit: 1,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            t.set(snap.ref, { status: 'Redeemed', redemptionId: redemption.id, promoCode: code }, { merge: true });
        } else {
            t.set(snap.ref, { status: 'Redeemed', redemptionId: redemption.id }, { merge: true });
        }
    }).catch(async error => snap.ref.set({ status: 'Rejected', reason: error.message }, { merge: true })); return null;
});

// When an order is cancelled, reverse any loyalty points that were awarded.
exports.reverseLoyaltyOnCancellation = functions.firestore.document('orders/{orderId}').onWrite(async (change, context) => {
    const orderId = context.params.orderId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return null;
    const beforeStatus = before ? before.status : null;
    if (after.status !== 'Cancelled' || beforeStatus === 'Cancelled') return null;
    const customerId = after.userId || after.customerId;
    if (!customerId) return null;
    const txRef = db.collection('loyalty_transactions').doc(orderId);
    const txSnap = await txRef.get();
    if (!txSnap.exists || txSnap.data().type !== 'earn') return null;
    const pointsToReverse = Number(txSnap.data().points || 0);
    if (!pointsToReverse || pointsToReverse <= 0) return null;
    const balanceRef = db.collection('loyalty_balances').doc(customerId);
    await db.runTransaction(async t => {
        const tx = await t.get(txRef);
        if (!tx.exists || tx.data().type !== 'earn' || tx.data().reversed) return;
        const balance = await t.get(balanceRef);
        const current = balance.exists ? Number(balance.data().points || 0) : 0;
        t.set(txRef, { reversed: true, reversedPoints: pointsToReverse, reversedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        t.set(balanceRef, { customerId, points: Math.max(0, current - pointsToReverse), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        t.set(db.collection('loyalty_transactions').doc(`${orderId}_reverse`), {
            orderId, customerId, points: -pointsToReverse, type: 'reverse', reason: 'Order cancelled', createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
    });
    return null;
});
