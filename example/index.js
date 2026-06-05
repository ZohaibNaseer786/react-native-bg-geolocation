/**
 * App entry point.
 *
 * Importing './src/backgroundLocationService' at module scope registers the
 * headless task immediately — exactly like the production app does. This is
 * what makes kill-state JS execution work: the task is registered before the
 * app is ever killed, so the native HeadlessJsTaskService can find it.
 */
import { AppRegistry } from 'react-native';
import App from './src/App';
import { name as appName } from './app.json';

// Side-effect import: registers the headless task at module scope.
import './src/backgroundLocationService';

AppRegistry.registerComponent(appName, () => App);
