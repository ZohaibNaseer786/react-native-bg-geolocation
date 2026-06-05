import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'BG Geolocation — Tracking Viewer',
  description: 'Visualise saved location points on a map',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          fontFamily: 'system-ui, -apple-system, sans-serif',
          background: '#0d1117',
        }}
      >
        {children}
      </body>
    </html>
  );
}
