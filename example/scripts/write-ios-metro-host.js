#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const outputPath = path.join(projectRoot, 'ios', '.metro-host');

const explicitHost =
  process.env.RCT_METRO_HOST ||
  process.env.METRO_HOST ||
  process.env.REACT_NATIVE_PACKAGER_HOSTNAME;

function isUsableIPv4(address) {
  return (
    /^\d{1,3}(\.\d{1,3}){3}$/.test(address) &&
    !address.startsWith('127.') &&
    !address.startsWith('169.254.')
  );
}

function getPreferredHost() {
  if (explicitHost && isUsableIPv4(explicitHost)) {
    return explicitHost;
  }

  const interfaces = os.networkInterfaces();
  const preferredNames = ['en0', 'en1', 'en2'];

  for (const name of preferredNames) {
    for (const details of interfaces[name] || []) {
      if (details.family === 'IPv4' && !details.internal && isUsableIPv4(details.address)) {
        return details.address;
      }
    }
  }

  for (const detailsList of Object.values(interfaces)) {
    for (const details of detailsList || []) {
      if (details.family === 'IPv4' && !details.internal && isUsableIPv4(details.address)) {
        return details.address;
      }
    }
  }

  return null;
}

const host = getPreferredHost();

if (!host) {
  console.warn('[ios] Could not find a LAN IP for Metro. Physical devices may fall back to bundled JS.');
  process.exit(0);
}

fs.writeFileSync(outputPath, `${host}\n`);
console.log(`[ios] Metro host for physical devices: ${host}`);
