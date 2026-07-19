/// <reference types="node" />
import { defineConfig } from "vitepress";

const base = process.env.DOCS_BASE_PATH || "/";
const githubRepo = "https://github.com/samolabams/systems-design-lab";

export default defineConfig({
  title: "Systems Design Lab",
  description: "Runnable systems-design lessons with local infrastructure demos.",
  base,
  cleanUrls: true,
  lastUpdated: true,
  themeConfig: {
    logo: {
      src: "/logo.svg",
      alt: "Systems Design Lab"
    },
    nav: [
      { text: "Guide", link: "/guide/" },
      { text: "Modules", link: "/modules/" },
      { text: "GitHub", link: githubRepo }
    ],
    sidebar: [
      {
        text: "Start",
        items: [
          { text: "Welcome", link: "/" },
          { text: "Guide", link: "/guide/" },
          { text: "Modules", link: "/modules/" }
        ]
      },
      {
        text: "Foundations",
        items: [
          { text: "Introduction", link: "/modules/introduction/" },
          { text: "Design Method", link: "/modules/design-method/" },
          { text: "Estimation", link: "/modules/estimation/" },
          { text: "When Not To Scale", link: "/modules/when-not-to-scale/" },
          { text: "Component Selection", link: "/modules/component-selection/" },
          { text: "Consistency", link: "/modules/consistency-models/" },
          { text: "Availability", link: "/modules/availability/" }
        ]
      },
      {
        text: "Components",
        items: [
          { text: "DNS", link: "/modules/dns/" },
          { text: "Load Balancing", link: "/modules/load-balancing/" },
          { text: "API Gateway", link: "/modules/api-gateway/" },
          { text: "Scaling", link: "/modules/scaling/" },
          { text: "Service Discovery", link: "/modules/service-discovery/" },
          { text: "Databases", link: "/modules/databases/" },
          { text: "Database Scaling", link: "/modules/database-scaling/" },
          { text: "Replication", link: "/modules/replication-failover/" },
          { text: "Leader Election", link: "/modules/leader-election-replica-sets/" },
          { text: "Sharding", link: "/modules/partitioning-sharding/" },
          { text: "Async Queues", link: "/modules/async-queues/" },
          { text: "Event Streaming", link: "/modules/event-streaming/" },
          { text: "Delivery Semantics", link: "/modules/message-delivery-semantics/" },
          { text: "Sagas", link: "/modules/sagas/" },
          { text: "Caching", link: "/modules/caching/" },
          { text: "Edge Caching", link: "/modules/edge-caching/" },
          { text: "Object Storage", link: "/modules/object-storage/" },
          { text: "API Design", link: "/modules/api-design/" },
          { text: "Rate Limiting", link: "/modules/rate-limiting/" },
          { text: "Circuit Breakers", link: "/modules/circuit-breakers/" },
          { text: "Observability", link: "/modules/observability/" },
          { text: "Multi-Region DR", link: "/modules/multi-region-dr/" },
          { text: "Vector Store", link: "/modules/vector-store/" }
        ]
      },
      {
        text: "Capstones",
        items: [
          { text: "TinyURL", link: "/modules/tinyurl/" },
          { text: "News Feed", link: "/modules/news-feed/" },
          { text: "Chat", link: "/modules/chat/" },
          { text: "Rate Limiter", link: "/modules/distributed-rate-limiter/" }
        ]
      }
    ],
    socialLinks: [
      { icon: "github", link: githubRepo }
    ],
    search: {
      provider: "local"
    },
    editLink: {
      pattern: `${githubRepo}/edit/main/docs/:path`,
      text: "Edit this page on GitHub"
    },
    footer: {
      message: "Built from the Systems Design Lab curriculum.",
      copyright: "Released under the MIT License."
    }
  }
});