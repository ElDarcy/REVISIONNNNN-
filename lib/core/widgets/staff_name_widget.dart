import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/formatters.dart';

/// A widget that displays the staff name based on its ID.
/// Uses a static cache to prevent blinking during parent list rebuilds.
class StaffNameWidget extends StatefulWidget {
  final String? staffId;
  final TextStyle? style;
  final String prefix;

  const StaffNameWidget({
    super.key,
    required this.staffId,
    this.style,
    this.prefix = 'Assigned to: ',
  });

  @override
  State<StaffNameWidget> createState() => _StaffNameWidgetState();
}

class _StaffNameWidgetState extends State<StaffNameWidget> {
  static final Map<String, String> _nameCache = {};
  Future<String>? _nameFuture;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(StaffNameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.staffId != oldWidget.staffId) {
      _initFuture();
    }
  }

  void _initFuture() {
    if (widget.staffId == null || widget.staffId!.isEmpty) {
      _nameFuture = Future.value('N/A');
      return;
    }

    if (_nameCache.containsKey(widget.staffId)) {
      _nameFuture = Future.value(_nameCache[widget.staffId]);
    } else {
      _nameFuture = _fetchName(widget.staffId!);
    }
  }

  Future<String> _fetchName(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        final rawName = data?['name'] as String? ?? 'Staff';
        final formattedName = Formatters.toTitleCase(rawName);
        _nameCache[id] = formattedName;
        return formattedName;
      }
    } catch (e) {
      debugPrint('Error fetching staff name: $e');
    }
    return 'Staff';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.staffId == null || widget.staffId!.isEmpty) {
      return Text('${widget.prefix}N/A', style: widget.style);
    }

    return FutureBuilder<String>(
      future: _nameFuture,
      builder: (context, snapshot) {
        // Only show "..." if we truly have no data and haven't fetched before
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Text('${widget.prefix}...', style: widget.style);
        }

        final name = snapshot.data ?? 'Staff';
        return Text('${widget.prefix}$name', style: widget.style);
      },
    );
  }
}
