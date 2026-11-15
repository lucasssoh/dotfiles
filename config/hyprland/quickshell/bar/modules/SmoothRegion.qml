import QtQuick
import Quickshell

// A Region whose rounded corners follow the antialiased pane drawn over
// it, for BackgroundEffect.blurRegion. Same properties as Region (x, y,
// width, height, radius and the four corner radii): swap the type, keep
// the rest.
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
// The rows are bindings on the root's geometry, never a deferred rebuild:
// a pane opening or closing moves every frame, and rows a frame late
// stuck out past the shrinking pane on both sides.
Region {
    id: root

    readonly property int _maxRows: 40

    function _inset(r, i) {
        if (i >= r)
            return 0;
        const dy = r - i - 0.5;
        return Math.max(0, Math.ceil(r - Math.sqrt(r * r - dy * dy) - 0.5));
    }

    // The corner rows, relative to the root's top-left: {y, h, l, r}.
    readonly property var _rects: {
        const w = root.width;
        const h = root.height;
        if (w <= 0 || h <= 0)
            return [];
        const half = Math.floor(Math.min(w, h) / 2);
        const clamp = (r) => Math.max(0, Math.min(root._maxRows, half, r));
        const tl = clamp(root.topLeftRadius), tr = clamp(root.topRightRadius);
        const bl = clamp(root.bottomLeftRadius), br = clamp(root.bottomRightRadius);
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

    // Rows are only ever added, never destroyed: a spare one binds to
    // nothing and stays empty.
    property list<Region> _pool

    function _grow() {
        if (root._pool.length >= root._rects.length)
            return;
        while (root._pool.length < root._rects.length)
            root._pool.push(rowComponent.createObject(root, { k: root._pool.length }));
        root.regions = root._pool;
    }

    on_RectsChanged: _grow()
    Component.onCompleted: _grow()

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
