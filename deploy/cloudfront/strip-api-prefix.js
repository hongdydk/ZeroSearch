/**
 * CloudFront Function (viewer request) for the /api* cache behavior.
 *
 * /api        -> /
 * /api/health -> /health
 */
function handler(event) {
  var request = event.request;

  if (request.uri === '/api') {
    request.uri = '/';
  } else if (request.uri.indexOf('/api/') === 0) {
    request.uri = request.uri.slice(4);
  }

  return request;
}
