/**
 * CloudFront Function (viewer request) for the default S3 cache behavior.
 *
 * Rewrite extensionless Flutter routes without turning API or missing asset
 * responses into index.html. Attach this only to the default S3 behavior.
 */
function handler(event) {
  var request = event.request;
  var lastSegment = request.uri.split('/').pop();

  if (request.uri.endsWith('/') || lastSegment.indexOf('.') === -1) {
    request.uri = '/index.html';
  }

  return request;
}
