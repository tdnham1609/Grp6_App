"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.reverseGeocodeAddress = reverseGeocodeAddress;
const NOMINATIM_REVERSE_URL = 'https://nominatim.openstreetmap.org/reverse';
const MIN_REQUEST_INTERVAL_MS = 1_000;
const REQUEST_TIMEOUT_MS = 5_000;
const addressCache = new Map();
const pendingLookups = new Map();
let requestQueue = Promise.resolve();
let lastRequestStartedAt = 0;
async function waitForRequestSlot() {
    const scheduledRequest = requestQueue.then(async () => {
        const waitMs = Math.max(0, lastRequestStartedAt + MIN_REQUEST_INTERVAL_MS - Date.now());
        if (waitMs > 0) {
            await new Promise((resolve) => setTimeout(resolve, waitMs));
        }
        lastRequestStartedAt = Date.now();
    });
    requestQueue = scheduledRequest.catch(() => undefined);
    await scheduledRequest;
}
/** Look up a human-readable nearby address for an explicitly shared GPS point. */
async function reverseGeocodeAddress(latitude, longitude) {
    if (!Number.isFinite(latitude) ||
        !Number.isFinite(longitude) ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
        return null;
    }
    const cacheKey = `${latitude.toFixed(5)},${longitude.toFixed(5)}`;
    const cachedAddress = addressCache.get(cacheKey);
    if (cachedAddress)
        return cachedAddress;
    const pending = pendingLookups.get(cacheKey);
    if (pending)
        return pending;
    const lookup = (async () => {
        try {
            await waitForRequestSlot();
            const url = new URL(NOMINATIM_REVERSE_URL);
            url.searchParams.set('format', 'jsonv2');
            url.searchParams.set('lat', String(latitude));
            url.searchParams.set('lon', String(longitude));
            url.searchParams.set('addressdetails', '1');
            url.searchParams.set('zoom', '18');
            const response = await fetch(url, {
                headers: {
                    'Accept-Language': 'vi,en',
                    'User-Agent': 'SinhTuSafetyApp/1.0 (classroom safety alert demo)',
                },
                signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
            });
            if (!response.ok)
                return null;
            const result = await response.json();
            if (typeof result !== 'object' ||
                result === null ||
                !('display_name' in result) ||
                typeof result.display_name !== 'string') {
                return null;
            }
            const address = result.display_name.trim();
            return address.length > 0 ? address : null;
        }
        catch (_) {
            return null;
        }
    })();
    pendingLookups.set(cacheKey, lookup);
    try {
        const address = await lookup;
        if (address)
            addressCache.set(cacheKey, address);
        return address;
    }
    finally {
        pendingLookups.delete(cacheKey);
    }
}
//# sourceMappingURL=reverseGeocoding.js.map