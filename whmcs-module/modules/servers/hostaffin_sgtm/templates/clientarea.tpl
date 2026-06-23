<!-- Hostaffin sGTM — client area panel template -->
<div class="hostaffin-panel">
  <h3>sGTM {{service.plan_slug|default:"Service"}}</h3>
  <p>
    Status: <strong>{{service.status|default:"unknown"}}</strong><br>
    Container URL:
    <code>https://{{service.edge_hostname}}</code>
  </p>

  <div class="row">
    <div class="col-md-6">
      <h4>Usage this month</h4>
      <ul>
        <li>Requests: {{usage.month.requests|default:0}}</li>
        <li>Bandwidth: {{usage.month.bandwidth_b|default:0}} bytes</li>
        <li>Loader hits: {{usage.month.loader_hits|default:0}}</li>
        <li>Cookie ext hits: {{usage.month.cookie_ext_hits|default:0}}</li>
      </ul>
    </div>

    <div class="col-md-6">
      <h4>Custom Domains</h4>
      <ul>
        {{range domains}}
          <li>{{.domain}} — SSL: {{.ssl_status}}, Verified: {{.verified}}</li>
        {{else}}
          <li><em>No custom domains.</em></li>
        {{end}}
      </ul>
    </div>
  </div>

  <h4>Custom Loader</h4>
  {{range loaders}}
    <pre>&lt;script async src="https://{{service.edge_hostname}}/loader.js?id={{.loader_id}}"&gt;&lt;/script&gt;</pre>
    <p>SRI: <code>{{.sri_hash|default:""}}</code></p>
  {{else}}
    <p><em>No loaders configured.</em></p>
  {{end}}

  <h4>Cookie Extensions</h4>
  <table class="table table-sm">
    <thead><tr><th>Cookie</th><th>Lifetime</th><th>Hits</th><th>Status</th></tr></thead>
    <tbody>
      {{range cookies}}
        <tr>
          <td>{{.cookie_name}}</td>
          <td>{{.new_lifetime_s}}s</td>
          <td>{{.hit_count}}</td>
          <td>{{if .is_active}}Active{{else}}Inactive{{end}}</td>
        </tr>
      {{else}}
        <tr><td colspan="4"><em>No cookie extensions configured.</em></td></tr>
      {{end}}
    </tbody>
  </table>
</div>