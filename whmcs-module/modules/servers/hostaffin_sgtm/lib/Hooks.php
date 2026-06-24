<?php
/**
 * Helper utilities used by the WHMCS module.
 */

class Hostaffin_Hooks
{
    /**
     * Returns a custom field value (or empty string).
     */
    public static function getServiceCustomField(int $serviceId, string $field): string
    {
        $row = Capsule::table('tblcustomfieldsvalues as v')
            ->join('tblcustomfields as f', 'f.id', '=', 'v.fieldid')
            ->where('v.relid', $serviceId)
            ->where('f.fieldname', $field)
            ->value('v.value');
        return $row !== null ? (string) $row : '';
    }

    /**
     * Sets a custom field value (creates the field if missing).
     */
    public static function setServiceCustomField(int $serviceId, string $field, string $value): void
    {
        $fieldId = Capsule::table('tblcustomfields')->where('fieldname', $field)->value('id');
        if (!$fieldId) {
            $fieldId = Capsule::table('tblcustomfields')->insertGetId([
                'type'       => 'product',
                'relid'      => 0,
                'fieldname'  => $field,
                'fieldtype'  => 'text',
                'description'=> 'Hostaffin sGTM — ' . $field,
                'regexpr'    => '',
                'adminonly'  => 'on',
                'required'   => '',
                'showorder'  => '',
                'showinvoice'=> '',
                'sortorder'  => 0,
            ]);
        }
        $existing = Capsule::table('tblcustomfieldsvalues')
            ->where('relid', $serviceId)
            ->where('fieldid', $fieldId)
            ->value('id');
        if ($existing) {
            Capsule::table('tblcustomfieldsvalues')
                ->where('id', $existing)
                ->update(['value' => $value]);
        } else {
            Capsule::table('tblcustomfieldsvalues')->insert([
                'relid'   => $serviceId,
                'fieldid' => $fieldId,
                'value'   => $value,
            ]);
        }
    }

    public static function logActivity(int $serviceId, string $message): void
    {
        if (function_exists('logActivity')) {
            logActivity($message);
        }
    }

    /**
     * CSRF token check for any state-changing form action in the client area.
     */
    public static function checkCsrf(): void
    {
        $token = $_POST['token'] ?? '';
        $ok = false;
        if (class_exists('\WHMCS\Session')) {
            $ok = \WHMCS\Session::get('uid') && hash_equals(
                (string) \WHMCS\Session::get('csrfToken'),
                (string) $token
            );
        }
        // Fallback: WHMCS exposes a per-request token in smarty {$token}
        if (!$ok && function_exists('generateToken')) {
            $ok = hash_equals((string) $_SESSION['token'] ?? '', (string) $token);
        }
        if (!$ok) {
            http_response_code(403);
            echo '<div class="alert alert-danger">Invalid CSRF token. Please reload the page and try again.</div>';
            exit;
        }
    }

    /**
     * Format a unix timestamp (or null) as a WHMCS-style date.
     */
    public static function fmtDate(?string $iso): string
    {
        if (!$iso) return '—';
        $ts = strtotime($iso);
        return $ts ? date('Y-m-d H:i', $ts) : htmlspecialchars($iso);
    }

    /**
     * Human-readable byte size.
     */
    public static function fmtBytes($n): string
    {
        $n = (int) $n;
        if ($n < 1024) return $n . ' B';
        $units = ['KB', 'MB', 'GB', 'TB'];
        $i = -1;
        do { $n = $n / 1024; $i++; } while ($n >= 1024 && $i < count($units) - 1);
        return number_format($n, 2) . ' ' . $units[$i];
    }

    /**
     * Format an integer with thousands separators.
     */
    public static function fmtInt($n): string
    {
        return number_format((int) $n);
    }

    /**
     * Returns the list of common JS-file aliases clients can pick.
     */
    public static function jsAliasOptions(): array
    {
        return [
            'gtm.js'     => 'gtm.js (default Google Tag Manager)',
            'trk-ss.js'  => 'trk-ss.js (server-side tracking)',
            'trk.js'     => 'trk.js (generic tracker)',
            'gtag.js'    => 'gtag.js (Google gtag)',
            'analytics.js' => 'analytics.js (Universal Analytics)',
            'fbevents.js' => 'fbevents.js (Facebook Pixel)',
            'pixel.js'   => 'pixel.js (Pixel-style)',
            'loader.js'  => 'loader.js (generic)',
            'custom'     => 'custom (let me specify)',
        ];
    }

    /**
     * Returns the list of well-known cookie name pairs.
     */
    public static function cookieAliasPresets(): array
    {
        return [
            'meta'     => ['_fbp', '_fbc'],
            'ga4'      => ['_ga', '_ga_XXXXXX'],
            'mixpanel' => ['mp_xxx_mixpanel', 'mp_xxx_session'],
            'segment'  => ['ajs_anonymous_id', 'ajs_user_id'],
            'clarity'  => ['_clck', '_clsk'],
        ];
    }

    /**
     * Tiny template renderer (no third-party deps).
     *
     * Supports:
     *   {{var}}                         — escaped scalar
     *   {{var.path}}                    — dotted path lookup
     *   {{if var}} … {{else}} … {{end}} — truthiness / empty
     *   {{range items}} … {{else}} … {{end}}
     *   {{partial name}}                — include another template
     */
    public static function render(string $template, array $vars): string
    {
        if (!is_readable($template)) {
            return '';
        }
        $src = file_get_contents($template);
        return self::renderString($src, $vars, dirname($template));
    }

    public static function renderString(string $src, array $vars, ?string $baseDir = null): string
    {
        return self::parseBlocks($src, $vars, $baseDir, 0, strlen($src))[0];
    }

    /**
     * Recursive-descent renderer.
     * Returns [renderedString, endOffset] so nested blocks stop at their matching {{end}}.
     */
    private static function parseBlocks(string $src, array $vars, ?string $baseDir, int $start, int $end): array
    {
        $resolve = function ($key, $vars) {
            // {{.field}} — child item access (Go-template style)
            if (str_starts_with($key, '.') && $key !== '.') {
                $sub = substr($key, 1);
                $cur = $vars['.'] ?? '';
                if (is_array($cur) || is_object($cur)) {
                    foreach (explode('.', $sub) as $p) {
                        if (is_array($cur) && array_key_exists($p, $cur)) {
                            $cur = $cur[$p];
                        } elseif (is_object($cur) && isset($cur->$p)) {
                            $cur = $cur->$p;
                        } else {
                            return '';
                        }
                    }
                    return $cur;
                }
                return '';
            }
            $parts = explode('.', $key);
            $val = $vars;
            foreach ($parts as $p) {
                if (is_array($val) && array_key_exists($p, $val)) {
                    $val = $val[$p];
                } else {
                    return '';
                }
            }
            return $val;
        };
        $escape = function ($v) {
            if (is_scalar($v) || is_null($v)) {
                return htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
            }
            return htmlspecialchars(json_encode($v), ENT_QUOTES, 'UTF-8');
        };

        $out = '';
        $i = $start;
        while ($i < $end) {
            $open = strpos($src, '{{', $i);
            if ($open === false || $open >= $end) {
                $out .= substr($src, $i, $end - $i);
                break;
            }
            $out .= substr($src, $i, $open - $i);
            $close = strpos($src, '}}', $open + 2);
            if ($close === false) {
                $out .= substr($src, $open);
                break;
            }
            $inner = trim(substr($src, $open + 2, $close - $open - 2));

            // ---- {{partial name}} ----
            if (preg_match('/^partial\s+([a-zA-Z0-9_\.\/]+)$/', $inner, $m)) {
                $path = ($baseDir ?? __DIR__) . '/' . $m[1];
                if (!str_ends_with($path, '.tpl')) $path .= '.tpl';
                if (is_readable($path)) {
                    $out .= self::renderString(file_get_contents($path), $vars, dirname($path));
                }
                $i = $close + 2;
                continue;
            }

            // ---- {{range var}} … {{end}} ----
            if (preg_match('/^range\s+([a-zA-Z0-9_\.]+)$/', $inner, $m)) {
                $bodyStart = $close + 2;
                $bodyEnd = self::findMatchingEnd($src, $bodyStart);
                if ($bodyEnd === false) { $i = $close + 2; continue; }
                $body = substr($src, $bodyStart, $bodyEnd - $bodyStart);
                [$thenTpl, $elseTpl] = self::splitTopLevelElse($body);

                $val = $resolve($m[1], $vars);
                if (!empty($val) && (is_array($val) || $val instanceof \Traversable)) {
                    foreach ($val as $item) {
                        $childVars = $vars;
                        $childVars['.'] = $item;
                        $out .= self::renderString($thenTpl, $childVars, null);
                    }
                } else {
                    $out .= self::renderString($elseTpl, $vars, null);
                }
                $endPos = strpos($src, '}}', $bodyEnd);
                $i = ($endPos === false) ? strlen($src) : $endPos + 2;
                continue;
            }

            // ---- {{if var}} … {{else}} … {{end}} ----
            if (preg_match('/^if\s+([a-zA-Z0-9_\.]+)$/', $inner, $m)) {
                $bodyStart = $close + 2;
                $bodyEnd = self::findMatchingEnd($src, $bodyStart);
                if ($bodyEnd === false) { $i = $close + 2; continue; }
                $body = substr($src, $bodyStart, $bodyEnd - $bodyStart);
                [$thenTpl, $elseTpl] = self::splitTopLevelElse($body);
                $val = $resolve($m[1], $vars);
                $truthy = !empty($val) && $val !== '0' && $val !== 'false';
                $out .= self::renderString($truthy ? $thenTpl : $elseTpl, $vars, null);
                $endPos = strpos($src, '}}', $bodyEnd);
                $i = ($endPos === false) ? strlen($src) : $endPos + 2;
                continue;
            }

            // ---- {{var.path|filter}} — supports the very common
            // {{var|default:X}} pipe so the template is friendly.
            if (preg_match('/^([a-zA-Z0-9_\.]+)\s*\|\s*([a-zA-Z0-9_]+)\s*(?::\s*(.*))?$/', $inner, $m)) {
                $val = $resolve($m[1], $vars);
                $filter = $m[2];
                if ($filter === 'default') {
                    $def = trim($m[3] ?? '');
                    if ($val === '' || $val === null || $val === false) {
                        $val = $def;
                    }
                    $out .= $escape($val);
                } elseif ($filter === 'raw' || $filter === 'safe') {
                    // Render without HTML escaping
                    $out .= (string) ($val ?? '');
                } elseif ($filter === 'upper') {
                    $out .= $escape(strtoupper((string) $val));
                } elseif ($filter === 'lower') {
                    $out .= $escape(strtolower((string) $val));
                } else {
                    $out .= $escape($val);
                }
                $i = $close + 2;
                continue;
            }

            // ---- {{var.path}} or {{.field}} ----
            if (preg_match('/^[a-zA-Z0-9_\.]+$/', $inner)) {
                if ($inner === '.') {
                    $out .= $escape($vars['.'] ?? '');
                } else {
                    $out .= $escape($resolve($inner, $vars));
                }
                $i = $close + 2;
                continue;
            }

            // Unknown tag — leave as-is
            $out .= substr($src, $open, $close - $open + 2);
            $i = $close + 2;
        }
        return [$out, $i];
    }

    /**
     * Find offset of the {{ that opens the matching {{end}} for a block
     * starting at $start (which should be just after the opening }} of the block).
     */
    private static function findMatchingEnd(string $src, int $start): int|false
    {
        $depth = 1;
        $i = $start;
        while ($i < strlen($src)) {
            $open = strpos($src, '{{', $i);
            if ($open === false) return false;
            $close = strpos($src, '}}', $open + 2);
            if ($close === false) return false;
            $inner = trim(substr($src, $open + 2, $close - $open - 2));
            if (preg_match('/^(range|if)\s+/', $inner)) {
                $depth++;
            } elseif ($inner === 'end') {
                $depth--;
                if ($depth === 0) return $open;
            }
            $i = $close + 2;
        }
        return false;
    }

    /**
     * Split a block body on its top-level {{else}}, ignoring {{else}} that
     * appear inside nested {{range}} / {{if}}.
     */
    private static function splitTopLevelElse(string $body): array
    {
        $depth = 0;
        $i = 0;
        while ($i < strlen($body)) {
            $open = strpos($body, '{{', $i);
            if ($open === false) break;
            $close = strpos($body, '}}', $open + 2);
            if ($close === false) break;
            $inner = trim(substr($body, $open + 2, $close - $open - 2));
            if (preg_match('/^(range|if)\s+/', $inner)) {
                $depth++;
            } elseif ($inner === 'end') {
                if ($depth > 0) $depth--;
            } elseif (preg_match('/^else$/', $inner) && $depth === 0) {
                return [substr($body, 0, $open), substr($body, $close + 2)];
            }
            $i = $close + 2;
        }
        return [$body, ''];
    }
}