pragma Singleton
import QtQuick
import Quickshell

// Pure helpers behind EECalcPreview: SI parsing/formatting, E-series
// lookup and resistor colour bands. No state.
Singleton {
    id: root

    readonly property var series: ({
        E12: [1.0, 1.2, 1.5, 1.8, 2.2, 2.7, 3.3, 3.9, 4.7, 5.6, 6.8, 8.2],
        E24: [1.0, 1.1, 1.2, 1.3, 1.5, 1.6, 1.8, 2.0, 2.2, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.3, 4.7, 5.1, 5.6, 6.2, 6.8, 7.5, 8.2, 9.1],
        E96: [1.00, 1.02, 1.05, 1.07, 1.10, 1.13, 1.15, 1.18, 1.21, 1.24, 1.27, 1.30, 1.33, 1.37, 1.40, 1.43, 1.47, 1.50, 1.54, 1.58, 1.62, 1.65, 1.69, 1.74, 1.78, 1.82, 1.87, 1.91, 1.96, 2.00, 2.05, 2.10, 2.15, 2.21, 2.26, 2.32, 2.37, 2.43, 2.49, 2.55, 2.61, 2.67, 2.74, 2.80, 2.87, 2.94, 3.01, 3.09, 3.16, 3.24, 3.32, 3.40, 3.48, 3.57, 3.65, 3.74, 3.83, 3.92, 4.02, 4.12, 4.22, 4.32, 4.42, 4.53, 4.64, 4.75, 4.87, 4.99, 5.11, 5.23, 5.36, 5.49, 5.62, 5.76, 5.90, 6.04, 6.19, 6.34, 6.49, 6.65, 6.81, 6.98, 7.15, 7.32, 7.50, 7.68, 7.87, 8.06, 8.25, 8.45, 8.66, 8.87, 9.09, 9.31, 9.53, 9.76]
    })

    readonly property var prefixes: ({ p: 1e-12, n: 1e-9, u: 1e-6, "µ": 1e-6, m: 1e-3, "": 1, R: 1, r: 1, k: 1e3, K: 1e3, M: 1e6, G: 1e9 })

    // "4.7k", "4k7", "1R5", "100n", "3.3", "10 kΩ", "20mA" -> number, or
    // NaN. Case matters for m (milli) vs M (mega).
    function parse(text) {
        const m = /^\s*(\d+(?:\.\d+)?|\.\d+)\s*([pnuµmkKMGRr]?)(\d*)\s*(?:Ω|ohms?|[VvAaFfHh])?\s*$/.exec(text ?? "");
        if (!m || (m[3] && (m[1].includes(".") || !m[2])))
            return NaN;
        return parseFloat(m[1] + (m[3] ? "." + m[3] : "")) * root.prefixes[m[2]];
    }

    // 4700, "Ω" -> "4.7 kΩ"; three significant figures, trailing zeros
    // dropped.
    function format(v, unit) {
        if (!isFinite(v))
            return "—";
        if (v === 0)
            return "0 " + unit;
        const steps = [[1e9, "G"], [1e6, "M"], [1e3, "k"], [1, ""], [1e-3, "m"], [1e-6, "µ"], [1e-9, "n"], [1e-12, "p"]];
        const a = Math.abs(v);
        const [scale, prefix] = steps.find(s => a >= s[0] * 0.9995) ?? steps[steps.length - 1];
        return parseFloat((v / scale).toPrecision(3)) + " " + prefix + unit;
    }

    // Nearest value of series `name` to v: "nearest" by ratio, "up" the
    // smallest at or above v, "down" the largest at or below.
    function nearest(v, name, mode) {
        if (!(v > 0))
            return NaN;
        const base = root.series[name];
        const decade = Math.floor(Math.log10(v));
        const cands = [];
        for (const d of [decade - 1, decade, decade + 1])
            for (const b of base)
                cands.push(parseFloat((b * Math.pow(10, d)).toPrecision(3)));
        const eps = v * 1e-9;
        if (mode === "up")
            return cands.filter(c => c >= v - eps).reduce((a, c) => Math.min(a, c), Infinity);
        if (mode === "down")
            return cands.filter(c => c <= v + eps).reduce((a, c) => Math.max(a, c), 0);
        return cands.reduce((a, c) => Math.abs(Math.log(c / v)) < Math.abs(Math.log(a / v)) ? c : a);
    }

    // Percent difference of `actual` from `wanted`, signed, e.g. "+2.1%".
    function errorPct(actual, wanted) {
        const e = (actual - wanted) / wanted * 100;
        return (e >= 0 ? "+" : "") + e.toFixed(Math.abs(e) < 10 ? 1 : 0) + "%";
    }

    readonly property var colors: [
        { name: "black", color: "#1a1a1a" },
        { name: "brown", color: "#7b4a1e" },
        { name: "red", color: "#d93030" },
        { name: "orange", color: "#f08a24" },
        { name: "yellow", color: "#f2d43d" },
        { name: "green", color: "#3aa655" },
        { name: "blue", color: "#3d6fd9" },
        { name: "violet", color: "#8f4fd1" },
        { name: "grey", color: "#8a8a8a" },
        { name: "white", color: "#f2f2f2" }
    ]
    readonly property var gold: ({ name: "gold", color: "#c9a227" })
    readonly property var silver: ({ name: "silver", color: "#b8bcc2" })

    // Colour bands for resistance v with `digits` significant digits (2 ->
    // 4-band, 5% gold tolerance; 3 -> 5-band, 1% brown). Returns
    // { bands: [{name, color}], value (what the bands actually read),
    // exact (bands == v) } or null if out of range.
    function bands(v, digits) {
        if (!(v > 0))
            return null;
        let exp = Math.floor(Math.log10(v)) - (digits - 1);
        let sig = Math.round(v / Math.pow(10, exp));
        if (sig >= Math.pow(10, digits)) {
            sig = Math.round(sig / 10);
            exp += 1;
        }
        // Multiplier bands run silver (10^-2) .. white (10^9).
        if (exp < -2 || exp > 9)
            return null;
        const out = String(sig).padStart(digits, "0").split("").map(d => root.colors[Number(d)]);
        out.push(exp === -1 ? root.gold : exp === -2 ? root.silver : root.colors[exp]);
        out.push(digits === 2 ? root.gold : root.colors[1]);
        const value = parseFloat((sig * Math.pow(10, exp)).toPrecision(digits));
        return { bands: out, value: value, exact: Math.abs(value - v) <= v * 1e-9 };
    }
}
