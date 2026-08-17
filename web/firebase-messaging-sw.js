importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

firebase.initializeApp({
  apiKey: "AIzaSyCq7wNcDcHRCzCcq_NzcpFWNl2cfsfwRGs",
  appId: "1:917614781066:web:174403cabd9c0f994bc373",
  messagingSenderId: "917614781066",
  projectId: "laundrycaps2",
  authDomain: "laundrycaps2.firebaseapp.com",
  storageBucket: "laundrycaps2.firebasestorage.app",
});

const messaging = firebase.messaging();
