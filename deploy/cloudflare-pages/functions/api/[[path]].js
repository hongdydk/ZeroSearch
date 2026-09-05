import { proxyToMallApi } from '../_proxy.js';

export async function onRequest(context) {
  return proxyToMallApi(context);
}
