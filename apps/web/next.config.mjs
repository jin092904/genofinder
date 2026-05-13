/** @type {import('next').NextConfig} */
const API_PROXY_TARGET =
  process.env.API_BASE_URL ?? "http://localhost:8000";

const nextConfig = {
  reactStrictMode: true,
  output: "standalone",
  typedRoutes: true,
  images: {
    remotePatterns: [
      // Google 프로필 사진 (Firebase Auth user.photoURL)
      { protocol: "https", hostname: "lh3.googleusercontent.com" },
      { protocol: "https", hostname: "lh4.googleusercontent.com" },
      { protocol: "https", hostname: "lh5.googleusercontent.com" },
      { protocol: "https", hostname: "lh6.googleusercontent.com" },
    ],
  },
  // 브라우저 fetch 가 cross-origin (3000→8000) 으로 가면 CORS preflight 가 필요해지고
  // Chrome 의 PNA (private network access) / disk cache / WSL 포트 forwarding 까지
  // 변수 많아짐. 같은 origin 으로 묶어서 next dev server 가 server-side 로 backend 에
  // proxy 하면 preflight 자체가 사라짐.
  async rewrites() {
    return [
      {
        source: "/backend/:path*",
        destination: `${API_PROXY_TARGET}/api/v1/:path*`,
      },
    ];
  },
};

export default nextConfig;
