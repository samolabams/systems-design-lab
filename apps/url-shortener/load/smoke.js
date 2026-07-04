// k6 smoke test: shorten a URL then follow the redirect, through the gateway.
// Run via `make load`. Env: GATEWAY (default http://gateway:80 inside compose).
import http from 'k6/http';
import { check, sleep } from 'k6';

const GATEWAY = __ENV.GATEWAY || 'http://gateway:80';

export const options = {
  scenarios: {
    smoke: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '10s', target: 10 },
        { duration: '20s', target: 10 },
        { duration: '5s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  // Write path.
  const res = http.post(`${GATEWAY}/shorten`, JSON.stringify({ url: 'https://example.com' }), {
    headers: { 'Content-Type': 'application/json' },
  });
  check(res, { 'shorten 201': (r) => r.status === 201 });

  // Read path: follow the redirect (manual to assert the 302).
  if (res.status === 201) {
    const code = res.json('code');
    const look = http.get(`${GATEWAY}/${code}`, { redirects: 0 });
    check(look, { 'redirect 302': (r) => r.status === 302 });
  }

  sleep(0.5);
}
