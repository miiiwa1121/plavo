"use strict";
// File generated from our OpenAPI spec by Stainless. See CONTRIBUTING.md for details.
Object.defineProperty(exports, "__esModule", { value: true });
exports.RateLimits = void 0;
const resource_1 = require("../../../core/resource.js");
const pagination_1 = require("../../../core/pagination.js");
class RateLimits extends resource_1.APIResource {
    /**
     * List Messages API rate limits for your organization.
     *
     * Each entry corresponds to one rate-limit group (either a model family or an
     * API-surface category such as the Files API or Message Batches) and contains the
     * set of limiter values that apply to it.
     *
     * This endpoint currently returns every matching entry in a single page regardless
     * of `limit`; follow `next_page` so that clients keep working when pagination is
     * enabled.
     *
     * @example
     * ```ts
     * // Automatically fetches more pages as needed.
     * for await (const betaOrganizationRateLimit of client.beta.organization.rateLimits.list()) {
     *   // ...
     * }
     * ```
     */
    list(query = {}, options) {
        return this._client.getAPIList('/v1/organizations/rate_limits?beta=true', (pagination_1.PageCursor), { query, ...options });
    }
}
exports.RateLimits = RateLimits;
//# sourceMappingURL=rate-limits.js.map