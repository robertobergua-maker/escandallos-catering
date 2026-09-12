const UPSTREAM_HOST = "escandallos.streamlit.app";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const originalHost = url.hostname;

    url.hostname = UPSTREAM_HOST;
    url.protocol = "https:";

    const upstreamRequest = new Request(url, request);
    upstreamRequest.headers.set("Host", UPSTREAM_HOST);
    upstreamRequest.headers.set("Origin", `https://${UPSTREAM_HOST}`);

    const response = await fetch(upstreamRequest);

    if (response.webSocket) {
      response.webSocket.accept({ allowHalfOpen: true });
      return new Response(null, { status: 101, webSocket: response.webSocket });
    }

    const headers = new Headers(response.headers);
    const location = headers.get("Location");
    if (location && location.includes(UPSTREAM_HOST)) {
      headers.set("Location", location.replace(UPSTREAM_HOST, originalHost));
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  },
};
