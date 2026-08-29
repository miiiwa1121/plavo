// File generated from our OpenAPI spec by Stainless. See CONTRIBUTING.md for details.
import { APIResource } from "../../../core/resource.mjs";
import { PageCursor } from "../../../core/pagination.mjs";
export class RateLimits extends APIResource {
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
        return this._client.getAPIList('/v1/organizations/rate_limits?beta=true', (PageCursor), { query, ...options });
    }
}
//# sourceMappingURL=rate-limits.mjs.map