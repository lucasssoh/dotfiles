import QtQuick
import Quickshell

// A Region whose rounded corners follow the antialiased pane drawn over
// it, for BackgroundEffect.blurRegion. Same properties as Region (x, y,
// width, height, radius and the four corner radii), plus the window's
// `pixelRatio`: swap the type, keep the rest.
//
// Region's own radius steps its corners conservatively: a pixel is kept
// only if it lies wholly inside the arc, so the top row starts a full
// radius in. The antialiased arc of the pane above covers 2-3 more pixels
// per corner row, and those sit on the unblurred desktop -- with
// blur.brightness at 0.50 that is twice as bright as the blurred one, so
// every glass pane grew a light, jagged halo on its corners.
//
// Here a pixel is kept when its centre lies inside the arc: the region
// stops where the arc's coverage crosses 50%, and the stairs fall within
// the antialiased pixels instead of beside them. The root keeps its own
// rect (a subset of the smooth shape); child rows add the corner pixels
// it leaves out, one rect per run of rows with the same insets.
//
// At a fractional scale (1.25) the region is still in whole logical
// pixels, and Hyprland rounds every one of its rects OUT to whole screen
// pixels: each corner row grew by up to a pixel on every side, the root's
// own rounded corners with it, and the blur showed past the pane's edge
// as dark stairs around every glass popup. So there the rows follow an
// arc pulled in by what that rounding adds on average, and the root's
// corners are cut away first, leaving the rows alone to shape them. At a
// whole scale nothing is rounded and nothing changes.
//
// The rows are bindings on the root's geometry, never a deferred rebuild:
// a pane opening or closing moves every frame, and rows a frame late
// stuck out past the shrinking pane on both sides.
Region {
    id: root

    property int maxRows: 40
    // The window's devicePixelRatio (Hyprland's scale for its screen). A
    // Region cannot reach its window, so the window passes it.
    property real pixelRatio: 1

    // How far the rounding out pushes an edge, on average, in logical
    // pixels. The scale is a fraction over 120 (fractional-scale-v1); in
    // lowest terms n/q, edges land on q evenly spread phases, and rounding
    // out adds (q - 1) / 2q of a screen pixel. 1.25 = 5/4: 3/8 of a
    // pixel, 0.3 logical. Whole scales: 0.
    readonly property real _shrink: {
        const n = Math.round(root.pixelRatio * 120);
        if (n <= 0)
            return 0;
        let a = n, b = 120;
        while (b) {
            const t = a % b;
            a = b;
            b = t;
        }
        const q = 120 / a;
        return (q - 1) / (2 * q) / root.pixelRatio;
    }

    function _inset(r, i) {
        if (i >= r)
            return 0;
        const dy = r - i - 0.5;
        const rr = r - root._shrink;
        return Math.max(0, Math.ceil(r - Math.sqrt(Math.max(0, rr * rr - dy * dy)) - 0.5));
    }

    // The corners' radii, clamped to what the rows can carry.
    readonly property var _radii: {
        const w = root.width;
        const h = root.height;
        if (w <= 0 || h <= 0)
            return { tl: 0, tr: 0, bl: 0, br: 0 };
        const half = Math.floor(Math.min(w, h) / 2);
        const clamp = (r) => Math.max(0, Math.min(root.maxRows, half, r));
        return {
            tl: clamp(root.topLeftRadius), tr: clamp(root.topRightRadius),
            bl: clamp(root.bottomLeftRadius), br: clamp(root.bottomRightRadius)
        };
    }

    // The corner rows, relative to the root's top-left: {y, h, l, r}.
    readonly property var _rects: {
        const h = root.height;
        const rd = root._radii;
        const tl = rd.tl, tr = rd.tr, bl = rd.bl, br = rd.br;
        if (root.width <= 0 || h <= 0)
            return [];
        const rects = [];
        const push = (y, l, r) => {
            const last = rects.length > 0 ? rects[rects.length - 1] : null;
            if (last && last.l === l && last.r === r && last.y + last.h === y)
                last.h += 1;
            else
                rects.push({ y: y, h: 1, l: l, r: r });
        };
        const top = Math.max(tl, tr);
        for (let i = 0; i < top; i++)
            push(i, root._inset(tl, i), root._inset(tr, i));
        const bottom = Math.max(bl, br);
        for (let i = bottom - 1; i >= 0; i--)
            push(h - 1 - i, root._inset(bl, i), root._inset(br, i));
        return rects;
    }

    // The four corner cuts come first (children apply in order), then the
    // rows. Rows are only ever added, never destroyed: a spare one binds
    // to nothing and stays empty.
    property list<Region> _cuts
    property list<Region> _pool

    function _grow() {
        if (root._cuts.length === 0) {
            for (let c = 0; c < 4; c++)
                root._cuts.push(cutComponent.createObject(root, { c: c }));
        } else if (root._pool.length >= root._rects.length) {
            return;
        }
        while (root._pool.length < root._rects.length)
            root._pool.push(rowComponent.createObject(root, { k: root._pool.length }));
        const all = [];
        for (let c = 0; c < root._cuts.length; c++)
            all.push(root._cuts[c]);
        for (let k = 0; k < root._pool.length; k++)
            all.push(root._pool[k]);
        root.regions = all;
    }

    on_RectsChanged: _grow()
    Component.onCompleted: _grow()

    // A corner's square, taken out of the root: empty at a whole scale.
    property Component _cutComponent: Component {
        id: cutComponent

        Region {
            required property int c
            readonly property int size: root._shrink <= 0 ? 0
                : c === 0 ? root._radii.tl : c === 1 ? root._radii.tr
                : c === 2 ? root._radii.bl : root._radii.br
            intersection: Intersection.Subtract
            x: root.x + (c % 2 === 1 ? root.width - size : 0)
            y: root.y + (c >= 2 ? root.height - size : 0)
            width: size
            height: size
        }
    }

    property Component _rowComponent: Component {
        id: rowComponent

        Region {
            required property int k
            readonly property var rc: k < root._rects.length ? root._rects[k] : null
            x: rc ? root.x + rc.l : 0
            y: rc ? root.y + rc.y : 0
            width: rc ? root.width - rc.l - rc.r : 0
            height: rc ? rc.h : 0
        }
    }
}
