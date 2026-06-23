/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  async rewrites() {
    const cp = process.env.NEXT_PUBLIC_CONTROL_PLANE_URL || 'http://localhost:8080';
    return [
      {
        source: '/api/cp/:path*',
        destination: `${cp}/api/:path*`,
      },
    ];
  },
};
export default nextConfig;