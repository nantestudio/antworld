/// AI Hive Mind Service - Strategic intelligence for ant colonies
///
/// Uses Supabase Edge Functions to call OpenAI APIs securely,
/// with anonymous auth and proper RLS for data isolation.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'hive_mind_models.dart';

/// Singleton service managing AI-powered colony decisions
class HiveMindService {
  HiveMindService._();
  static final instance = HiveMindService._();

  // Configuration
  static const _decisionInterval = Duration(seconds: 30);
  static const _requestTimeout = Duration(seconds: 45);
  static const _maxFailuresBeforeDisable = 3;
  static const _disableDuration = Duration(minutes: 5);
  static const _decisionCacheTtl = Duration(seconds: 60);
  static const _maxLogEntries = 50;

  // State
  final ValueNotifier<bool> enabled = ValueNotifier(true);
  final ValueNotifier<bool> isProcessing = ValueNotifier(false);
  final ValueNotifier<HiveMindDecision?> lastDecision = ValueNotifier(null);
  final List<HiveMindLogEntry> decisionLog = [];

  // Session management
  String? _sessionId;
  String get sessionId => _sessionId ??= const Uuid().v4();

  // Decision caching
  HiveMindDecision? _pendingDecision;
  DateTime? _lastDecisionTime;
  DateTime? _lastRequestTime;

  // Failure tracking for graceful degradation
  int _consecutiveFailures = 0;
  bool _isDisabledDueToFailures = false;
  Timer? _reenableTimer;

  // Supabase client
  SupabaseClient? _supabase;
  bool _isInitialized = false;

  /// Initialize the service with Supabase
  Future<void> initialize({
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    if (_isInitialized) return;

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      _supabase = Supabase.instance.client;

      // Sign in anonymously for RLS with device metadata
      final session = _supabase!.auth.currentSession;
      if (session == null) {
        final metadata = await _buildUserMetadata();
        await _supabase!.auth.signInAnonymously(data: metadata);
        debugPrint('HiveMind: Signed in anonymously with metadata');
      }

      _isInitialized = true;
      debugPrint('HiveMind: Initialized successfully');
    } catch (e) {
      debugPrint('HiveMind: Initialization failed: $e');
      _isInitialized = false;
    }
  }

  /// Check if service is ready to make requests
  bool get isReady =>
      _isInitialized && enabled.value && !_isDisabledDueToFailures;

  /// Request a strategic decision from the AI (async, non-blocking)
  ///
  /// Call this periodically (every 30s recommended). Results are cached
  /// and can be consumed via [consumePendingDecision].
  Future<void> requestDecisionAsync(HiveMindStateSnapshot snapshot) async {
    if (!isReady) return;
    if (isProcessing.value) return;

    // Throttle requests
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _decisionInterval) return;
    }

    isProcessing.value = true;
    _lastRequestTime = DateTime.now();

    try {
      final decision = await _fetchDecision(snapshot);

      if (decision != null) {
        _pendingDecision = decision;
        _lastDecisionTime = DateTime.now();
        lastDecision.value = decision;

        // Add to log
        decisionLog.insert(
          0,
          HiveMindLogEntry(
            timestamp: DateTime.now(),
            decision: decision,
          ),
        );
        if (decisionLog.length > _maxLogEntries) {
          decisionLog.removeLast();
        }

        // Store suggested memory from AI (if any)
        if (decision.suggestedMemory != null &&
            decision.suggestedMemory!.isNotEmpty) {
          final memory = ColonyMemory(
            sessionId: sessionId,
            colonyId: 0, // Global insight
            category: 'ai_insight',
            content: decision.suggestedMemory!,
            createdAt: DateTime.now(),
          );
          storeMemory(memory);
        }

        _handleSuccess();
        debugPrint('HiveMind: Decision received - ${decision.reasoning}');
      }
    } catch (e) {
      debugPrint('HiveMind: Decision request failed: $e');
      _handleFailure();
    } finally {
      isProcessing.value = false;
    }
  }

  /// Consume a pending decision (call from update loop)
  ///
  /// Returns the decision once, then clears it. Returns null if no
  /// decision is pending or if the cached decision has expired.
  HiveMindDecision? consumePendingDecision() {
    if (_pendingDecision == null) return null;
    if (_lastDecisionTime == null) return null;

    // Check if decision has expired
    final elapsed = DateTime.now().difference(_lastDecisionTime!);
    if (elapsed > _decisionCacheTtl) {
      _pendingDecision = null;
      return null;
    }

    final decision = _pendingDecision;
    _pendingDecision = null;
    return decision;
  }

  /// Store a memory for future context
  Future<void> storeMemory(ColonyMemory memory) async {
    if (!isReady) return;

    try {
      await _supabase!.functions.invoke(
        'antworld-hive-mind-remember',
        body: {
          'sessionId': sessionId,
          'colonyId': memory.colonyId,
          'category': memory.category,
          'content': memory.content,
        },
      );
      debugPrint('HiveMind: Memory stored - ${memory.category}');
    } catch (e) {
      debugPrint('HiveMind: Failed to store memory: $e');
    }
  }

  /// Reset session (call on new game)
  void resetSession() {
    _sessionId = const Uuid().v4();
    _pendingDecision = null;
    _lastDecisionTime = null;
    _lastRequestTime = null;
    decisionLog.clear();
    debugPrint('HiveMind: Session reset - $_sessionId');
  }

  /// Fetch decision from edge function
  Future<HiveMindDecision?> _fetchDecision(
    HiveMindStateSnapshot snapshot,
  ) async {
    if (_supabase == null) return null;

    final response = await _supabase!.functions
        .invoke(
          'antworld-hive-mind-decide',
          body: {
            'sessionId': sessionId,
            'snapshot': snapshot.toJson(),
          },
        )
        .timeout(_requestTimeout);

    if (response.status != 200) {
      throw Exception('Edge function returned ${response.status}');
    }

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('No data in response');
    }

    return HiveMindDecision.fromJson(data);
  }

  void _handleSuccess() {
    _consecutiveFailures = 0;
    if (_isDisabledDueToFailures) {
      _isDisabledDueToFailures = false;
      _reenableTimer?.cancel();
      debugPrint('HiveMind: Re-enabled after recovery');
    }
  }

  void _handleFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxFailuresBeforeDisable) {
      _isDisabledDueToFailures = true;
      debugPrint('HiveMind: Temporarily disabled due to failures');

      // Schedule re-enable
      _reenableTimer?.cancel();
      _reenableTimer = Timer(_disableDuration, () {
        _isDisabledDueToFailures = false;
        _consecutiveFailures = 0;
        debugPrint('HiveMind: Re-enabled after timeout');
      });
    }
  }

  /// Clean up resources
  void dispose() {
    _reenableTimer?.cancel();
  }

  /// Build user metadata for anonymous sign-in (multi-tenant tracking)
  Future<Map<String, dynamic>> _buildUserMetadata() async {
    String platform = 'unknown';
    String deviceModel = 'unknown';
    bool isTablet = false;

    try {
      if (kIsWeb) {
        platform = 'Web';
        deviceModel = 'Browser';
      } else if (Platform.isIOS) {
        platform = 'iOS ${Platform.operatingSystemVersion}';
        // iOS model detection would need device_info_plus for details
        deviceModel = 'iPhone';
      } else if (Platform.isAndroid) {
        platform = 'Android ${Platform.operatingSystemVersion}';
        deviceModel = 'Android Device';
      } else if (Platform.isMacOS) {
        platform = 'macOS ${Platform.operatingSystemVersion}';
        deviceModel = 'Mac';
      } else if (Platform.isWindows) {
        platform = 'Windows ${Platform.operatingSystemVersion}';
        deviceModel = 'Windows PC';
      } else if (Platform.isLinux) {
        platform = 'Linux ${Platform.operatingSystemVersion}';
        deviceModel = 'Linux PC';
      }
    } catch (e) {
      debugPrint('HiveMind: Failed to get platform info: $e');
    }

    String appVersion = '1.0.0';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
    } catch (e) {
      debugPrint('HiveMind: Failed to get app version: $e');
    }

    final now = DateTime.now();
    final timezone = now.timeZoneName;

    return {
      'app': 'antworld',
      'app_version': appVersion,
      'platform': platform,
      'device_model': deviceModel,
      'is_tablet': isTablet,
      'timezone': timezone,
      'created_at': now.toUtc().toIso8601String(),
      'device_fingerprint': sessionId, // Use session ID as fingerprint
    };
  }
}
