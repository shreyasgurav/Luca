const url = require('url');
const fetch = require('node-fetch');
const config = require('../config');

function sendJSON(res, status, data) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(data));
}

async function searchPlaces(req, res) {
  try {
    if (!config.GOOGLE_PLACES_API_KEY) return sendJSON(res, 400, { error: 'GOOGLE_PLACES_API_KEY not set' });
    const parsed = url.parse(req.url, true);
    const q = (parsed.query.query || 'salon').toString();
    const lat = parseFloat(parsed.query.lat);
    const lng = parseFloat(parsed.query.lng);
    const radius = Math.min(parseInt(parsed.query.radius || '2000', 10) || 2000, 10000);
    const openNow = parsed.query.open_now === 'true';
    if (!isFinite(lat) || !isFinite(lng)) return sendJSON(res, 400, { error: 'Missing lat/lng' });

    // Use Text Search (better relevance) with location bias
    const endpoint = 'https://maps.googleapis.com/maps/api/place/textsearch/json';
    const params = new URLSearchParams({
      query: q,
      location: `${lat},${lng}`,
      radius: String(radius),
      opennow: openNow ? 'true' : undefined,
      key: config.GOOGLE_PLACES_API_KEY
    });
    // Clean undefined
    [...params.keys()].forEach(k => { if (params.get(k) === 'undefined') params.delete(k); });

    const resp = await fetch(`${endpoint}?${params.toString()}`);
    const data = await resp.json();
    if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
      return sendJSON(res, 502, { error: 'Places API error', status: data.status, message: data.error_message });
    }
    const results = (data.results || []).slice(0, 10).map(r => ({
      id: r.place_id,
      name: r.name,
      rating: r.rating,
      user_ratings_total: r.user_ratings_total,
      address: r.formatted_address,
      open_now: r.opening_hours?.open_now,
      lat: r.geometry?.location?.lat,
      lng: r.geometry?.location?.lng,
      distance_m: haversineMeters(lat, lng, r.geometry?.location?.lat, r.geometry?.location?.lng),
      google_maps_url: `https://www.google.com/maps/place/?q=place_id:${r.place_id}`,
      apple_maps_url: `http://maps.apple.com/?q=${encodeURIComponent(r.name)}&ll=${r.geometry?.location?.lat},${r.geometry?.location?.lng}`
    })).sort((a, b) => (a.distance_m ?? 0) - (b.distance_m ?? 0));

    return sendJSON(res, 200, { query: q, count: results.length, results });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  if (![lat1, lon1, lat2, lon2].every(v => typeof v === 'number' && isFinite(v))) return undefined;
  const R = 6371000;
  const toRad = deg => deg * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon/2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return Math.round(R * c);
}

module.exports = async function handler(req, res) {
  const pathname = url.parse(req.url).pathname;
  if (pathname === '/api/places/search' && req.method === 'GET') return searchPlaces(req, res);
  res.statusCode = 404; res.end('Not found');
};


