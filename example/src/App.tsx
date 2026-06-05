import { useEffect, useRef, useState } from 'react';
import {
  Alert,
  Animated,
  AppState,
  type AppStateStatus,
  DevSettings,
  Linking,
  NativeModules,
  PermissionsAndroid,
  Platform,
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  ToastAndroid,
  TouchableOpacity,
  View,
} from 'react-native';
import BackgroundGeolocation, {
  type Location,
} from 'react-native-bg-geolocation';
import {
  setBgLocationHooks,
  startBackgroundTracking,
  stopBackgroundTracking,
} from './backgroundLocationService';
import { SERVER_BASE_URL } from './locationSocketService';

const JS_DEBUG_MARKER = 'ios-debug-marker-2026-06-05-2145';

type PermStatus = 'unknown' | 'whenInUse' | 'always' | 'denied';
type MotionState = 'unknown' | 'moving' | 'stationary';
type SocketState = 'disconnected' | 'connecting' | 'connected';

// ─── Toast ──────────────────────────────────────────────────────────────────
let _showIosToast: ((msg: string) => void) | null = null;
function showToast(message: string) {
  if (Platform.OS === 'android') {
    ToastAndroid.showWithGravity(
      message,
      ToastAndroid.LONG,
      ToastAndroid.BOTTOM
    );
  } else {
    _showIosToast?.(message);
  }
}
function IosToast() {
  const [message, setMessage] = useState('');
  const opacity = useRef(new Animated.Value(0)).current;
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    _showIosToast = (msg: string) => {
      if (timer.current) clearTimeout(timer.current);
      setMessage(msg);
      Animated.sequence([
        Animated.timing(opacity, {
          toValue: 1,
          duration: 250,
          useNativeDriver: true,
        }),
        Animated.delay(2500),
        Animated.timing(opacity, {
          toValue: 0,
          duration: 400,
          useNativeDriver: true,
        }),
      ]).start();
      timer.current = setTimeout(() => setMessage(''), 3200);
    };
    return () => {
      _showIosToast = null;
    };
  }, [opacity]);
  if (!message) return null;
  return (
    <Animated.View style={[styles.iosToast, { opacity }]} pointerEvents="none">
      <Text style={styles.iosToastText}>{message}</Text>
    </Animated.View>
  );
}

// ─── Permissions ──────────────────────────────────────────────────────────────
function iosStatusLabel(code: number): PermStatus {
  switch (code) {
    case BackgroundGeolocation.AUTHORIZATION_STATUS_ALWAYS:
      return 'always';
    case BackgroundGeolocation.AUTHORIZATION_STATUS_WHEN_IN_USE:
      return 'whenInUse';
    case BackgroundGeolocation.AUTHORIZATION_STATUS_DENIED:
    case BackgroundGeolocation.AUTHORIZATION_STATUS_RESTRICTED:
      return 'denied';
    default:
      return 'unknown';
  }
}

async function requestAndroidPermissions(): Promise<void> {
  await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
    {
      title: 'Location Permission',
      message: 'Precise location is required.',
      buttonPositive: 'Allow',
      buttonNegative: 'Deny',
    }
  );
  if (Number(Platform.Version) >= 33) {
    await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS,
      {
        title: 'Notification',
        message: 'Shown while tracking is active.',
        buttonPositive: 'Allow',
        buttonNegative: 'Deny',
      }
    ).catch(() => {});
  }
  if (Number(Platform.Version) >= 29) {
    // @ts-ignore ACTIVITY_RECOGNITION exists on API 29+
    await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.ACTIVITY_RECOGNITION,
      {
        title: 'Physical Activity',
        message: 'Detects moving vs. stationary.',
        buttonPositive: 'Allow',
        buttonNegative: 'Deny',
      }
    ).catch(() => {});
    await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION,
      {
        title: 'Always-On Location',
        message: 'Choose "Allow all the time".',
        buttonPositive: 'Continue',
        buttonNegative: 'Skip',
      }
    );
  }
}

// ─── App ──────────────────────────────────────────────────────────────────────
export default function App() {
  const [enabled, setEnabled] = useState(false);
  const [permStatus, setPermStatus] = useState<PermStatus>('unknown');
  const [motionState, setMotion] = useState<MotionState>('unknown');
  const [activity, setActivity] = useState('—');
  const [socketState, setSocket] = useState<SocketState>('disconnected');
  const [appStateLabel, setAppStateLabel] = useState<AppStateStatus>(
    (AppState.currentState ?? 'active') as AppStateStatus
  );
  const [eventLog, setEventLog] = useState<string[]>([]);
  const [lastLoc, setLastLoc] = useState<{
    lat: number;
    lng: number;
    t: string;
  } | null>(null);

  useEffect(() => {
    // Wire the service's hooks to UI state
    setBgLocationHooks({
      onEvent: (msg) => {
        const ts = new Date().toLocaleTimeString();
        setEventLog((prev) => [`[${ts}] ${msg}`, ...prev].slice(0, 40));
      },
      onLocation: (loc: Location) => {
        setLastLoc({
          lat: loc.coords.latitude,
          lng: loc.coords.longitude,
          t: loc.timestamp,
        });
        setMotion(loc.is_moving ? 'moving' : 'stationary');
        if (loc.activity?.type)
          setActivity(`${loc.activity.type} ${loc.activity.confidence ?? 0}%`);
      },
      onMotionChange: (moving, act) => {
        setMotion(moving ? 'moving' : 'stationary');
        if (act) setActivity(act);
        showToast(moving ? '🚶 Moving' : '🧍 Stationary');
      },
      onEnabledChange: setEnabled,
      onSocketStatus: setSocket,
    });

    const sub = AppState.addEventListener('change', setAppStateLabel);
    checkPermission();
    return () => sub.remove();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const checkPermission = async () => {
    if (Platform.OS === 'android') {
      const fine = await PermissionsAndroid.check(
        PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION
      );
      if (fine) {
        const bg =
          Number(Platform.Version) >= 29
            ? await PermissionsAndroid.check(
                PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION
              )
            : true;
        setPermStatus(bg ? 'always' : 'whenInUse');
      } else {
        setPermStatus('unknown');
      }
    } else {
      try {
        const p = await BackgroundGeolocation.getProviderState();
        setPermStatus(iosStatusLabel(p.status));
      } catch {
        setPermStatus('unknown');
      }
    }
  };

  const onToggle = async () => {
    if (enabled) {
      await stopBackgroundTracking();
      setEnabled(false);
      showToast('⏹ Tracking stopped');
      return;
    }
    // Request permissions first
    if (Platform.OS === 'android') {
      await requestAndroidPermissions();
      await checkPermission();
    }
    const result = await startBackgroundTracking();
    if (Platform.OS === 'ios')
      setPermStatus(iosStatusLabel(result.permissionStatus));
    if (result.started) {
      setEnabled(true);
      showToast('▶ Tracking started — socket delivery');
    } else {
      showToast('⚠️ "Always" permission required');
      Alert.alert(
        'Permission needed',
        'Enable "Always" location in Settings.',
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Open Settings', onPress: () => Linking.openSettings() },
        ]
      );
    }
  };

  const onGetPosition = async () => {
    try {
      const loc = await BackgroundGeolocation.getCurrentPosition({
        samples: 1,
        timeout: 30,
      });
      setLastLoc({
        lat: loc.coords.latitude,
        lng: loc.coords.longitude,
        t: loc.timestamp,
      });
      Alert.alert(
        'Current Position',
        `Lat: ${loc.coords.latitude.toFixed(6)}\nLng: ${loc.coords.longitude.toFixed(6)}\nMoving: ${loc.is_moving}\nActivity: ${loc.activity?.type}`
      );
    } catch (e: any) {
      Alert.alert('Error', e.toString());
    }
  };

  const onOpenDevMenu = () => {
    try {
      NativeModules.DevMenu?.show?.();
    } catch {
      showToast('Dev menu module is not available');
    }
  };

  // UI colors
  const permColor: Record<PermStatus, string> = {
    always: '#4ade80',
    whenInUse: '#f59e0b',
    denied: '#f87171',
    unknown: '#94a3b8',
  };
  const motColor: Record<MotionState, string> = {
    moving: '#38bdf8',
    stationary: '#a78bfa',
    unknown: '#94a3b8',
  };
  const sockColor: Record<SocketState, string> = {
    connected: '#4ade80',
    connecting: '#f59e0b',
    disconnected: '#f87171',
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0d1117" />

      <View style={styles.header}>
        <View>
          <Text style={styles.title}>BG Geolocation</Text>
          <Text style={styles.subtitle}>socket-only · app-level</Text>
        </View>
        <View
          style={[
            styles.dot,
            { backgroundColor: enabled ? '#4ade80' : '#475569' },
          ]}
        />
      </View>

      {/* Status grid */}
      <View style={styles.grid}>
        <Cell
          label="Permission"
          color={permColor[permStatus]}
          text={permStatus}
        />
        <Cell
          label="Socket"
          color={sockColor[socketState]}
          text={socketState}
        />
        <Cell label="Motion" color={motColor[motionState]} text={motionState} />
        <Cell label="Activity" text={activity} />
        <Cell label="App state" text={appStateLabel} />
        <Cell
          label="Last fix"
          text={
            lastLoc
              ? `${lastLoc.lat.toFixed(4)}, ${lastLoc.lng.toFixed(4)}`
              : '—'
          }
        />
      </View>

      <View style={styles.serverBar}>
        <Text style={styles.serverText} numberOfLines={1}>
          📡 {SERVER_BASE_URL}/socket/location
        </Text>
        <Text style={styles.debugMarker} numberOfLines={1}>
          JS marker {JS_DEBUG_MARKER} | __DEV__={String(__DEV__)}
        </Text>
      </View>

      {__DEV__ ? (
        <View style={styles.devRow}>
          <TouchableOpacity style={styles.devBtn} onPress={onOpenDevMenu}>
            <Text style={styles.devBtnText}>Open Dev Menu</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.devBtn}
            onPress={() => DevSettings.reload('Manual reload from example')}
          >
            <Text style={styles.devBtnText}>Reload JS</Text>
          </TouchableOpacity>
        </View>
      ) : null}

      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[styles.btn, enabled ? styles.btnStop : styles.btnStart]}
          onPress={onToggle}
        >
          <Text style={styles.btnText}>{enabled ? '⏹  Stop' : '▶  Start'}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.btn} onPress={onGetPosition}>
          <Text style={styles.btnText}>📍 Get Position</Text>
        </TouchableOpacity>
      </View>

      <Text style={styles.sectionTitle}>Event Log ({eventLog.length})</Text>
      <ScrollView style={styles.log} contentContainerStyle={styles.logContent}>
        {eventLog.length === 0 ? (
          <Text style={styles.empty}>
            Tap ▶ Start to begin. Watch events stream here.
          </Text>
        ) : (
          eventLog.map((l, i) => (
            <Text key={i} style={styles.logLine}>
              {l}
            </Text>
          ))
        )}
      </ScrollView>

      <IosToast />
    </SafeAreaView>
  );
}

function Cell({
  label,
  text,
  color,
}: {
  label: string;
  text: string;
  color?: string;
}) {
  return (
    <View style={styles.cell}>
      <Text style={styles.cellLabel}>{label}</Text>
      {color ? (
        <View style={[styles.badge, { backgroundColor: color + '22' }]}>
          <View style={[styles.badgeDot, { backgroundColor: color }]} />
          <Text style={[styles.badgeText, { color }]}>{text}</Text>
        </View>
      ) : (
        <Text style={styles.cellValue}>{text}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0d1117' },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    backgroundColor: '#161b22',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#30363d',
  },
  title: { color: '#e6edf3', fontSize: 17, fontWeight: '700' },
  subtitle: { color: '#8b949e', fontSize: 11, marginTop: 1 },
  dot: { width: 12, height: 12, borderRadius: 6 },

  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 8,
    paddingTop: 10,
  },
  cell: { width: '50%', paddingHorizontal: 8, paddingVertical: 6 },
  cellLabel: { color: '#8b949e', fontSize: 11, marginBottom: 3 },
  cellValue: { color: '#e6edf3', fontSize: 13, fontWeight: '600' },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 20,
    gap: 5,
    alignSelf: 'flex-start',
  },
  badgeDot: { width: 6, height: 6, borderRadius: 3 },
  badgeText: { fontSize: 11, fontWeight: '700' },

  serverBar: {
    marginHorizontal: 10,
    marginTop: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#161b22',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#30363d',
  },
  serverText: {
    color: '#58a6ff',
    fontSize: 11,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  debugMarker: {
    color: '#8b949e',
    fontSize: 10,
    marginTop: 5,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  devRow: {
    flexDirection: 'row',
    paddingHorizontal: 10,
    paddingTop: 8,
    gap: 8,
  },
  devBtn: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#30363d',
    alignItems: 'center',
  },
  devBtnText: { color: '#e6edf3', fontSize: 12, fontWeight: '700' },

  buttonRow: {
    flexDirection: 'row',
    paddingHorizontal: 10,
    paddingTop: 10,
    gap: 8,
  },
  btn: {
    flex: 1,
    paddingVertical: 11,
    borderRadius: 6,
    backgroundColor: '#1f6feb',
    alignItems: 'center',
  },
  btnStart: { backgroundColor: '#238636' },
  btnStop: { backgroundColor: '#da3633' },
  btnText: { color: '#e6edf3', fontSize: 13, fontWeight: '600' },

  sectionTitle: {
    color: '#64748b',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 6,
  },
  log: { flex: 1, paddingHorizontal: 10 },
  logContent: { paddingBottom: 20 },
  logLine: {
    color: '#8b949e',
    fontSize: 11,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    paddingVertical: 2,
  },
  empty: {
    color: '#484f58',
    textAlign: 'center',
    marginTop: 40,
    fontSize: 13,
    paddingHorizontal: 24,
    lineHeight: 20,
  },

  iosToast: {
    position: 'absolute',
    bottom: 40,
    alignSelf: 'center',
    backgroundColor: 'rgba(13,17,23,0.95)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
    maxWidth: '80%',
    borderWidth: 1,
    borderColor: '#30363d',
  },
  iosToastText: {
    color: '#e6edf3',
    fontSize: 13,
    fontWeight: '600',
    textAlign: 'center',
  },
});
