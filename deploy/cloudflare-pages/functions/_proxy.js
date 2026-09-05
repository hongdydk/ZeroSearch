/** Shared same-origin proxy for /api → mall-api origin. */
const DEFAULT_BACKEND = 'https://mall-api.anoveli.com';

function backendOrigin(env) {
  const raw = (env && env.MALL_API_ORIGIN) || DEFAULT_BACKEND;
  return String(raw).replace(/\/+$/, '');
}

export async function proxyToMallApi(context) {
  const { request, env } = context;
  const incoming = new URL(request.url);
  let path = incoming.pathname.replace(/^\/api/, '') || '/';
  if (!path.startsWith('/')) path = `/${path}`;

  const target = new URL(`${path}${incoming.search}`, `${backendOrigin(env)}/`);

  const headers = new Headers(request.headers);
  headers.delete('host');
  headers.set('host', target.host);

  const init = {
    method: request.method,
    headers,
    redirect: 'manual',
  };
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = request.body;
    init.duplex = 'half';
  }

  const upstream = await fetch(target.toString(), init);
  const out = new Headers(upstream.headers);
  out.delete('transfer-encoding');
  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: out,
  });
}
