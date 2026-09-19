import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

// Runs the tests inside workerd against the real Durable Object, not a mock of
// one. A relay tested against a fake relay would be the thing this project
// calls "a test that cannot fail".
export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        // The compatibility date comes from wrangler.toml and NOWHERE ELSE.
        // A `miniflare: { compatibilityDate }` here overrides it, which is how
        // the suite spent WP-4.1 running on a different runtime date than a
        // deploy would use — two places to state one fact, and the test copy
        // wins silently. One source of truth, and it is the one production reads.
        wrangler: { configPath: "./wrangler.toml" },
      },
    },
  },
});
