<!-- Hostaffin sGTM — client area panel (v1.2) -->
<style>
.hostaffin-panel { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 1100px; }
.hostaffin-panel h2 { border-bottom: 2px solid #1a73e8; padding-bottom: 6px; margin-top: 30px; }
.hostaffin-panel h3 { margin-top: 24px; color: #1a73e8; }
.hostaffin-panel .card { background: #fff; border: 1px solid #e0e0e0; border-radius: 6px; padding: 18px; margin-bottom: 18px; box-shadow: 0 1px 3px rgba(0,0,0,.05); }
.hostaffin-panel .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
.hostaffin-panel .grid-3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
.hostaffin-panel .stat { background: #f8f9fa; border-radius: 4px; padding: 12px; text-align: center; }
.hostaffin-panel .stat .v { font-size: 24px; font-weight: 600; color: #1a73e8; }
.hostaffin-panel .stat .l { font-size: 12px; color: #5f6368; }
.hostaffin-panel table { width: 100%; border-collapse: collapse; }
.hostaffin-panel th, .hostaffin-panel td { padding: 8px 10px; border-bottom: 1px solid #eee; text-align: left; font-size: 14px; }
.hostaffin-panel th { background: #f1f3f4; font-weight: 600; }
.hostaffin-panel pre { background: #202124; color: #e8eaed; padding: 12px; border-radius: 4px; overflow-x: auto; font-size: 12px; }
.hostaffin-panel .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
.hostaffin-panel .badge.ok { background: #e6f4ea; color: #137333; }
.hostaffin-panel .badge.warn { background: #fef7e0; color: #b06000; }
.hostaffin-panel .badge.err { background: #fce8e6; color: #c5221f; }
.hostaffin-panel .badge.idle { background: #f1f3f4; color: #5f6368; }
.hostaffin-panel form.inline { display: inline-block; }
.hostaffin-panel .form-row { display: flex; gap: 10px; align-items: flex-end; flex-wrap: wrap; margin-bottom: 10px; }
.hostaffin-panel .form-row label { display: flex; flex-direction: column; font-size: 12px; color: #5f6368; }
.hostaffin-panel .form-row input, .hostaffin-panel .form-row select, .hostaffin-panel .form-row textarea { padding: 6px 8px; border: 1px solid #dadce0; border-radius: 4px; font-size: 14px; }
.hostaffin-panel .btn { background: #1a73e8; color: #fff; border: 0; padding: 8px 14px; border-radius: 4px; cursor: pointer; font-size: 13px; }
.hostaffin-panel .btn:hover { background: #1557b0; }
.hostaffin-panel .btn.danger { background: #c5221f; }
.hostaffin-panel .btn.danger:hover { background: #a50e0e; }
.hostaffin-panel .btn.secondary { background: #5f6368; }
.hostaffin-panel details { margin: 10px 0; }
.hostaffin-panel details summary { cursor: pointer; color: #1a73e8; }
</style>

<div class="hostaffin-panel">

  {{if __flash}}
    <div class="card" style="background:#e6f4ea">
      <strong>✓</strong> {{__flash.msg}}
    </div>
  {{end}}

  <h2>sGTM Service</h2>
  <div class="card">
    <div class="grid-2">
      <div>
        <div>Plan: <strong>{{service.plan_slug}}</strong></div>
        <div>Status: {{service.status_badge|raw}}</div>
        <div>Container URL: <code>https://{{service.edge_hostname}}</code></div>
      </div>
      <div>
        <h4>Request count</h4>
        <div class="grid-3">
          <div class="stat">
            <div class="v">{{usage.month.requests|default:0}}</div>
            <div class="l">requests / month</div>
          </div>
          <div class="stat">
            <div class="v">{{usage.month.loader_hits|default:0}}</div>
            <div class="l">loader hits / month</div>
          </div>
          <div class="stat">
            <div class="v">{{usage.month.cookie_ext_hits|default:0}}</div>
            <div class="l">cookie hits / month</div>
          </div>
        </div>
        <p style="font-size:12px;color:#5f6368;margin-top:8px;">
          Bandwidth this month: <strong>{{usage.month.bandwidth_b|default:0}} bytes</strong>
        </p>
      </div>
    </div>
  </div>

  <!-- ───────────────── Custom Domains ───────────────── -->
  <h2>Custom Domains</h2>
  <div class="card">
    <h3>Add a new custom domain</h3>
    <form method="post" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}">
      <input type="hidden" name="token" value="{{__csrf}}">
      <input type="hidden" name="do" value="addDomain">
      <div class="form-row">
        <label>Domain
          <input type="text" name="domain" placeholder="track.example.com" required pattern="^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$">
        </label>
        <label>Primary
          <input type="checkbox" name="is_primary" value="1">
        </label>
        <button type="submit" class="btn">Add domain</button>
      </div>
    </form>

    <h3>Your domains</h3>
    {{if domains}}
      <table>
        <thead><tr><th>Domain</th><th>Verified</th><th>SSL</th><th>Actions</th></tr></thead>
        <tbody>
        {{range domains}}
          <tr>
            <td><code>{{.domain}}</code>{{if .is_primary}} <span class="badge ok">primary</span>{{end}}</td>
            <td>{{.verified_badge|raw}}</td>
            <td>{{.ssl_badge|raw}}</td>
            <td>
              {{if .needs_verify}}
                <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}">
                  <input type="hidden" name="token" value="{{__csrf}}">
                  <input type="hidden" name="do" value="verifyDomain">
                  <input type="hidden" name="domain_id" value="{{.id}}">
                  <button class="btn" type="submit">Re-verify</button>
                </form>
              {{end}}
              <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}"
                    onsubmit="return confirm('Remove this domain? Tracking on it will stop immediately.');">
                <input type="hidden" name="token" value="{{__csrf}}">
                <input type="hidden" name="do" value="deleteDomain">
                <input type="hidden" name="domain_id" value="{{.id}}">
                <button class="btn danger" type="submit">Remove</button>
              </form>
            </td>
          </tr>
        {{end}}
        </tbody>
      </table>
      <p style="font-size:12px;color:#5f6368;margin-top:8px;">
        To verify a domain, create a DNS CNAME pointing it to
        <code>{{service.edge_hostname}}</code>, then click <em>Re-verify</em>.
        ACME/Let's Encrypt will issue a cert automatically once the CNAME is live.
      </p>
    {{else}}
      <p><em>No custom domains yet. Add one above to start tracking on your own hostname.</em></p>
    {{end}}
  </div>

  <!-- ───────────────── Custom Loader ───────────────── -->
  <h2>Custom Loader</h2>
  <div class="card">
    <h3>Create a new loader</h3>
    <p style="font-size:12px;color:#5f6368;">
      Pick the JS file alias that matches your setup (e.g. <code>gtm.js</code>,
      <code>trk-ss.js</code> for server-side). If you track Facebook, the
      loader will forward <code>_fbp</code> / <code>_fbc</code> cookies so you
      can dedupe client vs server events.
    </p>
    <form method="post" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}">
      <input type="hidden" name="token" value="{{__csrf}}">
      <input type="hidden" name="do" value="createLoader">
      <div class="form-row">
        <label>JS file alias
          <select name="js_file_alias">
            {{range js_alias_options}}
              <option value="{{.key}}">{{.value}}</option>
            {{end}}
          </select>
        </label>
        <label>Mode
          <select name="mode">
            <option value="live">live</option>
            <option value="preview">preview</option>
          </select>
        </label>
        <label>Trigger
          <select name="trigger_type">
            <option value="immediate">immediate</option>
            <option value="delay">delay (ms)</option>
            <option value="consent">on consent cookie</option>
            <option value="element">on element</option>
          </select>
        </label>
        <label>Trigger value
          <input type="text" name="trigger_value" placeholder="e.g. 2000 or #cookie-banner">
        </label>
      </div>
      <div class="form-row">
        <label>FBP cookie name
          <input type="text" name="fbp_cookie_name" value="_fbp">
        </label>
        <label>FBC cookie name
          <input type="text" name="fbc_cookie_name" value="_fbc">
        </label>
        <label>Consent cookie name
          <input type="text" name="cookie_name" placeholder="(optional)">
        </label>
      </div>
      <div class="form-row">
        <label><input type="checkbox" name="respect_dnt" value="1" checked> Respect DNT</label>
        <label><input type="checkbox" name="honor_consent" value="1" checked> Honor consent cookie</label>
        <label><input type="checkbox" name="allow_bots" value="0"> Allow bots</label>
        <label>Vendor mapping (JSON, optional)
          <textarea name="vendor_mapping" rows="2" placeholder='{"facebook":{"id":"123"}}'></textarea>
        </label>
        <button type="submit" class="btn">Create loader</button>
      </div>
    </form>

    <h3>Your loaders</h3>
    {{if loaders}}
      <table>
        <thead><tr>
          <th>Loader ID</th><th>Alias</th><th>FBP/FBC</th><th>Trigger</th>
          <th>Hits</th><th>Status</th><th>Actions</th>
        </tr></thead>
        <tbody>
        {{range loaders}}
          <tr>
            <td><code>{{.loader_id}}</code></td>
            <td><code>{{.js_file_alias|default:gtm.js}}</code></td>
            <td><small>{{.fbp_cookie_name|default:_fbp}} / {{.fbc_cookie_name|default:_fbc}}</small></td>
            <td><small>{{.trigger_type}}{{if .trigger_value}} ({{.trigger_value}}){{end}}</small></td>
            <td>{{.hit_count|default:0}}</td>
            <td>
              {{if .is_active}}<span class="badge ok">active</span>
              {{else}}<span class="badge idle">disabled</span>{{end}}
            </td>
            <td>
              <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}">
                <input type="hidden" name="token" value="{{__csrf}}">
                <input type="hidden" name="do" value="toggleLoader">
                <input type="hidden" name="loader_id" value="{{.loader_id}}">
                <input type="hidden" name="op" value="{{if .is_active}}disable{{else}}enable{{end}}">
                <button class="btn secondary" type="submit">{{if .is_active}}Pause{{else}}Resume{{end}}</button>
              </form>
              <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}"
                    onsubmit="return confirm('Rotate this loader id? You will need to update your site.');">
                <input type="hidden" name="token" value="{{__csrf}}">
                <input type="hidden" name="do" value="regenerateLoader">
                <input type="hidden" name="loader_id" value="{{.loader_id}}">
                <button class="btn danger" type="submit">Rotate</button>
              </form>
            </td>
          </tr>
          <tr>
            <td colspan="7" style="background:#f8f9fa;">
              <details>
                <summary>Embed snippet for <code>{{.loader_id}}</code></summary>
                <pre>&lt;script async src="https://{{service.edge_hostname}}/{{.js_file_alias|default:gtm.js}}?id={{.loader_id}}"&gt;&lt;/script&gt;</pre>
                {{if .sri_hash}}<p style="font-size:12px;">SRI: <code>{{.sri_hash}}</code></p>{{end}}
                <p style="font-size:12px;color:#5f6368;">
                  Hits: <strong>{{.hit_count|default:0}}</strong> · Last hit: {{.last_hit_at|default:"—"}}
                </p>
              </details>
            </td>
          </tr>
        {{end}}
        </tbody>
      </table>
    {{else}}
      <p><em>No loaders configured yet.</em></p>
    {{end}}
  </div>

  <!-- ───────────────── Cookie Extensions ───────────────── -->
  <h2>Cookie Lifetime Extensions</h2>
  <div class="card">
    <p style="font-size:12px;color:#5f6368;">
      Extend the lifetime of third-party cookies (capped at Chrome's 395-day limit).
      Use this to keep Facebook <code>_fbp</code> / <code>_fbc</code>, Google <code>_ga</code>,
      and other vendor cookies alive beyond the browser's default 7-day cap.
    </p>

    <h3>Add a new extension</h3>
    <form method="post" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}">
      <input type="hidden" name="token" value="{{__csrf}}">
      <input type="hidden" name="do" value="createCookie">
      <div class="form-row">
        <label>Cookie name
          <input type="text" name="cookie_name" placeholder="_fbp" required>
        </label>
        <label>Vendor URL
          <input type="text" name="vendor_url" placeholder="https://connect.facebook.net" required>
        </label>
        <label>New lifetime (seconds)
          <input type="number" name="new_lifetime_s" value="34128000" min="1" max="34128000" required>
          <small>max 39,312,000s (395 days)</small>
        </label>
        <label>Path
          <input type="text" name="path" value="/">
        </label>
        <label>Cookie domain (optional)
          <input type="text" name="cookie_domain" placeholder=".example.com">
        </label>
      </div>
      <div class="form-row">
        <label>SameSite
          <select name="same_site">
            <option>Lax</option>
            <option>Strict</option>
            <option>None</option>
          </select>
        </label>
        <label><input type="checkbox" name="secure" value="1" checked> Secure</label>
        <label><input type="checkbox" name="http_only" value="0"> HTTP-only</label>
        <button type="submit" class="btn">Add extension</button>
      </div>
    </form>

    <h3>Active extensions</h3>
    {{if cookies}}
      <table>
        <thead><tr>
          <th>Cookie</th><th>Vendor</th><th>Lifetime</th><th>Path</th>
          <th>Hits</th><th>Status</th><th>Actions</th>
        </tr></thead>
        <tbody>
        {{range cookies}}
          <tr>
            <td><code>{{.cookie_name}}</code></td>
            <td><small>{{.vendor_url}}</small></td>
            <td>{{.new_lifetime_s}}s <small>(~{{.new_lifetime_s|default:0}}d)</small></td>
            <td><code>{{.path}}</code></td>
            <td>{{.hit_count|default:0}}</td>
            <td>
              <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}">
                <input type="hidden" name="token" value="{{__csrf}}">
                <input type="hidden" name="do" value="toggleCookie">
                <input type="hidden" name="cookie_id" value="{{.id}}">
                <input type="hidden" name="is_active" value="{{if .is_active}}0{{else}}1{{end}}">
                <label class="switch" style="display:inline-flex;align-items:center;gap:6px;cursor:pointer;">
                  <input type="checkbox" onchange="this.form.submit()" {{if .is_active}}checked{{end}}>
                  <span>{{if .is_active}}Active{{else}}Paused{{end}}</span>
                </label>
              </form>
            </td>
            <td>
              <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}"
                    onsubmit="return confirm('Remove this extension? The cookie will revert to its default lifetime.');">
                <input type="hidden" name="token" value="{{__csrf}}">
                <input type="hidden" name="do" value="deleteCookie">
                <input type="hidden" name="cookie_id" value="{{.id}}">
                <button class="btn danger" type="submit">Remove</button>
              </form>
            </td>
          </tr>
        {{end}}
        </tbody>
      </table>
    {{else}}
      <p><em>No cookie extensions yet.</em></p>
    {{end}}
  </div>

  <h2>Container</h2>
  <div class="card">
    <form method="post" class="inline" action="{{__action_path}}?a=ClientArea&modop=custom&id={{service_id}}"
          onsubmit="return confirm('Restart the sGTM container? This will briefly interrupt tracking.');">
      <input type="hidden" name="token" value="{{__csrf}}">
      <input type="hidden" name="do" value="restart">
      <button class="btn secondary" type="submit">Restart container</button>
    </form>
  </div>

</div>
