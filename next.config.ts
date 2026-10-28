import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  devIndicators: false,
  turbopack: { root: process.cwd() },
  experimental: { agentUpgrade: "security" },
};
export default nextConfig;
