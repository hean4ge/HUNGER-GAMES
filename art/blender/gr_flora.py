"""
gr_flora.py - GroundReal ground flora built from the card atlases (GR_Plants_*, GR_Shrubs_*).

Cards are bent quad grids whose UVs come from the trimmed atlas slots (GR atlas layout), so geometry size always
matches the rendered element at its texel density. Every card carries a real flipped back face (same UVs, same
custom normal) - no DoubleSided needed. Custom normals: grasses lean toward world up (they light like the ground
they stand on), fronds blend their own facing with up, bushes and the sapling crown use normals from the crown
centre (soft volumetric shading). Stems, stipes, trunks and branches are thin tubes mapped onto strip slots.
"""
import math

import numpy as np

import tex_ground as tg

PAGE = 1024.0
Z = np.array([0.0, 0.0, 1.0])


def nrm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def slot_rgb(page, names, weights=None):
    """Fallback MeshPart.Color (sRGB) for a part: weighted mean of the atlas slots it is mapped onto."""
    cols, ws = [], []
    for i, n in enumerate(names):
        c = page.get(n, {}).get("avg_srgb")
        if c:
            cols.append(c)
            ws.append(1.0 if weights is None else weights[i])
    if not cols:
        return None
    t = sum(ws)
    return [int(round(sum(c[k] * w for c, w in zip(cols, ws)) / t)) for k in range(3)]


# =============================================================================================== part builder
class Part:
    def __init__(self, layout):
        self.L = layout
        self.V, self.N, self.UV, self.F = [], [], [], []
        self.n = 0

    def _add(self, V, N, UV, F, double):
        V = np.asarray(V, float).reshape(-1, 3)
        N = np.asarray(N, float).reshape(-1, 3)
        UV = np.asarray(UV, float).reshape(-1, 2)
        base = self.n
        self.V.append(V)
        self.N.append(N)
        self.UV.append(UV)
        self.F += [tuple(int(i) + base for i in f) for f in F]
        self.n += len(V)
        if double:
            base2 = self.n
            self.V.append(V.copy())
            self.N.append(N.copy())
            self.UV.append(UV.copy())
            self.F += [tuple(int(i) + base2 for i in reversed(f)) for f in F]
            self.n += len(V)

    def empty(self):
        return self.n == 0

    def build(self, name):
        V = np.concatenate(self.V, 0)
        N = np.concatenate(self.N, 0)
        UV = np.concatenate(self.UV, 0)
        obj = tg.mesh_object(name, V, self.F)
        me = obj.data
        li = tg.loop_vertex_indices(me)
        tg.set_uvs(me, UV[li])
        tg.set_custom_normals(me, N[li])
        return obj

    # ------------------------------------------------------------------ slot helpers
    def slot(self, name):
        return self.L[name]

    def slot_axes(self, name, nu, nv, scale, sub=None):
        """Local card coordinates (studs) and UVs for a slot's trimmed rect (optionally a sub-rect in px)."""
        s = self.L[name]
        x0, y0, x1, y1 = sub if sub is not None else s["rect"]
        ax, ay = s["anchor_px"]
        d = s["density"]
        xs = np.linspace(x0, x1, nu + 1)
        ys = np.linspace(y0, y1, nv + 1)
        return (xs - ax) / d * scale, (ys - ay) / d * scale, xs / PAGE, ys / PAGE

    # ------------------------------------------------------------------ cards
    def card(self, name, origin, R, U, scale=1.0, nu=1, nv=3, bend=0.0, bend_dir=-1.0, bend_pow=1.5, fold=0.0,
             droop=0.0, normal_fn=None, double=True, sub=None, twist=0.0):
        """Bent card. R/U: unit right/up at the base (front normal N = R x U). bend: total rotation (rad) of the
        growth direction from base to top toward bend_dir * N. fold: V-fold (edges move toward +N by fold*|x|).
        droop: edges move toward -N by droop*(x/xmax)^2*width. twist: rotation (rad) of R about the growth
        direction from base to top."""
        R, U = nrm(R), nrm(U)
        N = np.cross(R, U)
        lx, ly, us, vs = self.slot_axes(name, nu, nv, scale, sub)
        ymax = max(ly.max(), 1e-6)
        xmax = max(np.abs(lx).max(), 1e-6)
        P = np.zeros((nv + 1, nu + 1, 3))
        # integrate the centreline from y = 0 (the anchor) in small steps
        steps = 64
        def centre(y):
            if y <= 0:
                return np.asarray(origin, float) + U * y, U, N
            ts = np.linspace(0, y, steps + 1)
            th = bend * np.clip(ts / ymax, 0, 1) ** bend_pow
            d = np.cos(th)[:, None] * U + np.sin(th)[:, None] * (bend_dir * N)
            c = np.asarray(origin, float) + ((d[1:] + d[:-1]) * 0.5).sum(0) * (y / steps)
            dy = d[-1]
            n_loc = np.cross(R, dy)
            return c, dy, nrm(n_loc)
        for j, y in enumerate(ly):
            c, dy, n_loc = centre(y)
            tw = twist * max(y, 0) / ymax
            r_loc = R * math.cos(tw) + n_loc * math.sin(tw)
            n_loc2 = nrm(np.cross(r_loc, dy))
            for i, x in enumerate(lx):
                p = c + r_loc * x
                p = p + n_loc2 * (fold * abs(x)) - n_loc2 * (droop * (x / xmax) ** 2 * xmax)
                P[j, i] = p
        # geometric normals from the grid
        Ng = np.zeros_like(P)
        for j in range(nv + 1):
            for i in range(nu + 1):
                du = P[j, min(i + 1, nu)] - P[j, max(i - 1, 0)]
                dv = P[min(j + 1, nv), i] - P[max(j - 1, 0), i]
                Ng[j, i] = nrm(np.cross(du, dv))
        UV = np.stack(np.meshgrid(us, vs), -1)
        Pf = P.reshape(-1, 3)
        Nf = Ng.reshape(-1, 3)
        Nc = np.array([normal_fn(p, n) for p, n in zip(Pf, Nf)]) if normal_fn else Nf
        F = []
        for j in range(nv):
            for i in range(nu):
                a = j * (nu + 1) + i
                F.append((a, a + 1, a + nu + 2, a + nu + 1))
        self._add(Pf, Nc, UV.reshape(-1, 2), F, double)
        return P

    def tube(self, pts, radii, sides, name, mode="stretch", double=False, cap=False, seg_studs=None,
             normal_fn=None):
        """Round stem along pts mapped onto a strip slot. mode 'stretch': the whole length spans the strip height;
        'repeat': true density, restarting the strip every seg_studs (a duplicated ring at each restart)."""
        pts = np.asarray(pts, float)
        k = len(pts)
        radii = np.full(k, radii) if np.ndim(radii) == 0 else np.asarray(radii, float)
        s = self.L[name]
        x0, y0, x1, y1 = s["slot"][0], s["slot"][1], s["slot"][0] + s["slot"][2], s["slot"][1] + s["slot"][3]
        pad = 2
        u0, u1 = (x0 + pad) / PAGE, (x1 - pad) / PAGE
        v0, v1 = (y0 + pad) / PAGE, (y1 - pad) / PAGE
        seglen = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
        total = max(seglen[-1], 1e-6)
        if mode == "repeat":
            seg = seg_studs or ((y1 - y0) / s["density"])
            vv = (seglen % seg) / seg
            restart = np.r_[False, np.floor(seglen[1:] / seg) > np.floor(seglen[:-1] / seg)]
        else:
            vv = seglen / total
            restart = np.zeros(k, bool)
        circ_u = min(1.0, (2 * math.pi * radii.max() * s["density"]) / max(x1 - x0 - 2 * pad, 1))
        V, N, UV, F = [], [], [], []
        rings = []
        for i in range(k):
            d = nrm(pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)])
            a = np.array([1.0, 0, 0]) if abs(d[0]) < 0.9 else np.array([0, 1.0, 0])
            s1 = nrm(np.cross(d, a))
            s2 = np.cross(d, s1)
            copies = [vv[i]] if not restart[i] else [1.0, vv[i]]
            ring_ids = []
            for vval in copies:
                ids = []
                for j in range(sides + 1):
                    ang = 2 * math.pi * j / sides
                    off = s1 * math.cos(ang) + s2 * math.sin(ang)
                    V.append(pts[i] + off * radii[i])
                    N.append(normal_fn(pts[i], off) if normal_fn else off)
                    UV.append((u0 + (u1 - u0) * (j / sides) * circ_u, v0 + (v1 - v0) * vval))
                    ids.append(len(V) - 1)
                ring_ids.append(ids)
            rings.append(ring_ids)
        for i in range(k - 1):
            ra = rings[i][-1]
            rb = rings[i + 1][0]
            for j in range(sides):
                F.append((ra[j], ra[j + 1], rb[j + 1], rb[j]))
        if cap:
            last = rings[-1][-1]
            c = len(V)
            V.append(pts[-1] + nrm(pts[-1] - pts[-2]) * radii[-1] * 0.3)
            N.append(nrm(pts[-1] - pts[-2]))
            UV.append(((u0 + u1) / 2, v1))
            for j in range(sides):
                F.append((last[j], last[j + 1], c))
        self._add(np.array(V), np.array(N), np.array(UV), F, double)

    def quad_islands(self, name, verts_list, normals_list, rng, scale=1.0):
        """Each polygon (list of 3D verts) becomes its own UV island inside a slot's trimmed rect at true density
        (random offset/rotation). Used for opaque fill textures on bush cores."""
        s = self.L[name]
        x0, y0, x1, y1 = s["rect"]
        d = s["density"] * scale
        for verts, nrms in zip(verts_list, normals_list):
            verts = np.asarray(verts, float)
            c = verts.mean(0)
            fn = nrm(np.cross(verts[1] - verts[0], verts[2] - verts[0]))
            a = np.array([1.0, 0, 0]) if abs(fn[0]) < 0.9 else np.array([0, 1.0, 0])
            e1 = nrm(np.cross(fn, a))
            e2 = np.cross(fn, e1)
            ang = rng.uniform(0, 2 * math.pi)
            e1, e2 = e1 * math.cos(ang) + e2 * math.sin(ang), -e1 * math.sin(ang) + e2 * math.cos(ang)
            loc = np.stack([(verts - c) @ e1, (verts - c) @ e2], 1) * d
            span = loc.max(0) - loc.min(0)
            if span[0] > (x1 - x0) or span[1] > (y1 - y0):
                loc *= min((x1 - x0) / max(span[0], 1), (y1 - y0) / max(span[1], 1)) * 0.98
                span = loc.max(0) - loc.min(0)
            ox = rng.uniform(x0 - loc[:, 0].min(), x1 - loc[:, 0].max()) if span[0] < (x1 - x0) else x0 - loc[:, 0].min()
            oy = rng.uniform(y0 - loc[:, 1].min(), y1 - loc[:, 1].max()) if span[1] < (y1 - y0) else y0 - loc[:, 1].min()
            uv = (loc + np.array([ox, oy])) / PAGE
            F = [tuple(range(len(verts)))]
            self._add(verts, nrms, uv, F, False)


# =============================================================================================== normal helpers
def up_blend(w):
    def f(p, n):
        n = n if n[2] >= 0 else -n
        return nrm(n * (1 - w) + Z * w)
    return f


def sphere_normals(center, w_sphere=0.75, w_up=0.1):
    center = np.asarray(center, float)

    def f(p, n):
        s = nrm(p - center)
        n = n if np.dot(n, s) >= 0 else -n
        return nrm(s * w_sphere + n * (1 - w_sphere - w_up) + Z * w_up)
    return f


def frame_yaw(yaw, lean=0.0, lean_dir=None):
    """Card frame for an upright card: R horizontal at yaw, U = up tilted by lean toward lean_dir (or the card's
    normal side)."""
    R0 = np.array([math.cos(yaw), math.sin(yaw), 0.0])
    if lean_dir is None:
        lean_dir = np.cross(R0, Z)
    U = nrm(Z * math.cos(lean) + nrm(lean_dir) * math.sin(lean))
    R = nrm(R0 - U * np.dot(U, R0))
    return R, U


# =============================================================================================== grasses
def grass_clump(part, rng, slots, n_center, n_outer, r_outer, scale_rng, lean_rng, bend_rng, nv=3, up_w=0.65,
                weights=None, fold=0.08):
    weights = weights or [1.0 / len(slots)] * len(slots)
    yaw0 = rng.uniform(0, math.pi)
    for k in range(n_center):
        yaw = yaw0 + math.pi * k / n_center + rng.uniform(-0.15, 0.15)
        side = rng.choice([-1.0, 1.0])
        R, U = frame_yaw(yaw, rng.uniform(*lean_rng) * 0.4 * side)
        sl = slots[rng.choice(len(slots), p=weights)]
        part.card(sl, (rng.normal(0, 0.05), rng.normal(0, 0.05), -0.05), R, U, rng.uniform(*scale_rng), nu=2, nv=nv,
                  bend=rng.uniform(*bend_rng), bend_dir=side, fold=fold, normal_fn=up_blend(up_w))
    for k in range(n_outer):
        a = 2 * math.pi * k / n_outer + rng.uniform(-0.3, 0.3)
        out = np.array([math.cos(a), math.sin(a), 0.0])
        r = r_outer * rng.uniform(0.55, 1.0)
        yaw = a + math.pi / 2 + rng.uniform(-0.6, 0.6)
        R, U = frame_yaw(yaw, rng.uniform(*lean_rng), out)
        N = np.cross(R, U)
        side = 1.0 if np.dot(N, out) > 0 else -1.0
        sl = slots[rng.choice(len(slots), p=weights)]
        part.card(sl, out * r + np.array([0, 0, -0.05]), R, U, rng.uniform(*scale_rng) * 0.88, nu=2, nv=nv,
                  bend=rng.uniform(*bend_rng) * 1.2, bend_dir=side, fold=fold, normal_fn=up_blend(up_w))


def build_grass_tall(lib, L, rng, variant):
    name = "GrassTallA" if variant == "a" else "GrassTallB"
    root = lib.begin(name, "Plant", ["Grass", "TallGrass", "Cover"],
                     "Golden tall-grass clump for the open field; alpha cards, no collision, no shadow.", budget=600)
    p = Part(L["Plants"])
    if variant == "a":
        grass_clump(p, rng, ["grass_tall_a", "grass_tall_b"], 4, 12, 0.7, (0.82, 1.0), (0.04, 0.2), (0.05, 0.35),
                    nv=3, up_w=0.6, weights=[0.8, 0.2])
    else:
        grass_clump(p, rng, ["grass_tall_b", "grass_tall_a"], 4, 11, 0.8, (0.72, 0.92), (0.1, 0.3), (0.2, 0.55),
                    nv=3, up_w=0.6, weights=[0.8, 0.2])
    ob = p.build(name + "_Grass")
    lib.add(root, ob, "Grass", "Plants", alpha="Transparency", backfaces=True,
            rgb=slot_rgb(L["Plants"], ["grass_tall_a", "grass_tall_b"], [0.8, 0.2] if variant == "a" else [0.2, 0.8]))
    lib.finish(root, ground_tol=0.08)
    return root


def build_grass_forest(lib, L, rng):
    root = lib.begin("GrassForest", "Plant", ["Grass", "GroundCover"],
                     "Green grass tuft for forest floor and meadow edges; scatter densely.", budget=600)
    p = Part(L["Plants"])
    grass_clump(p, rng, ["grass_forest_a", "grass_forest_b"], 3, 7, 0.35, (0.7, 0.95), (0.05, 0.25), (0.1, 0.45),
                nv=2, up_w=0.7, fold=0.05)
    ob = p.build("GrassForest_Grass")
    lib.add(root, ob, "Grass", "Plants", alpha="Transparency", backfaces=True,
            rgb=slot_rgb(L["Plants"], ["grass_forest_a", "grass_forest_b"]))
    lib.finish(root, ground_tol=0.08)
    return root


def build_flowers(lib, L, rng, variant):
    name = "FlowersA" if variant == "a" else "FlowersB"
    root = lib.begin(name, "Plant", ["Flowers", "GroundCover"],
                     ("Ox-eye daisies and buttercups in grass." if variant == "a" else
                      "Knapweed, yarrow, red clover and harebells in grass.") + " Side cards plus up-facing head cards.",
                     budget=600)
    p = Part(L["Plants"])
    main = "flowers_a" if variant == "a" else "flowers_b"
    grass_clump(p, rng, [main], 3, 3, 0.45, (0.8, 1.0), (0.03, 0.18), (0.05, 0.3), nv=2, up_w=0.6, fold=0.05)
    grass_clump(p, rng, ["grass_forest_a"], 2, 2, 0.5, (0.6, 0.8), (0.05, 0.2), (0.1, 0.4), nv=2, up_w=0.7)
    heads = [k for k in L["Plants"] if k.startswith("head_")]
    if variant == "a":
        pool = [h for h in heads if "daisy" in h or "buttercup" in h]
        nh, hz = 9, (0.9, 1.45)
    else:
        pool = [h for h in heads if any(t in h for t in ("knapweed", "clover", "harebell"))]
        nh, hz = 8, (0.55, 1.3)
    for k in range(nh):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.05, 0.55)
        h = pool[rng.randint(len(pool))]
        z = rng.uniform(*hz) * (0.6 if "clover" in h else 1.0)
        tilt = rng.uniform(0.1, 0.5)
        facing = nrm(Z + np.array([math.cos(a), math.sin(a), 0]) * tilt)
        R = nrm(np.cross(facing, np.array([math.sin(a), -math.cos(a), 0.3])))
        U = np.cross(facing, R)
        # head cards are centred: offset origin by the anchor so the flower sits at its stem
        p.card(h, np.array([math.cos(a) * r, math.sin(a) * r, z]), R, U, rng.uniform(0.9, 1.25), nu=1, nv=1,
               normal_fn=up_blend(0.4))
    ob = p.build(name + "_Flower")
    lib.add(root, ob, "Flower", "Plants", alpha="Transparency", backfaces=True,
            rgb=slot_rgb(L["Plants"], [main, "grass_forest_a"], [0.6, 0.4]))
    lib.finish(root, ground_tol=0.08)
    return root


# =============================================================================================== ferns
def build_fern_bracken(lib, L, rng):
    root = lib.begin("FernA", "Plant", ["Fern", "Bracken", "Cover"],
                     "Bracken: upright stipes carrying broad near-horizontal triangular blades (~2.6 tall).",
                     budget=900)
    p = Part(L["Plants"])
    nfr = 9
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(nfr):
        yaw = i * golden + rng.uniform(-0.3, 0.3)
        out = np.array([math.cos(yaw), math.sin(yaw), 0.0])
        young = i % 4 == 3
        h = rng.uniform(0.8, 1.25) if young else rng.uniform(1.35, 2.6)
        base = out * rng.uniform(0.05, 0.75) + np.array([0, 0, -0.06])
        lean = rng.uniform(0.15, 0.35)
        ts = np.linspace(0, 1, 5)
        pts = [base + out * (lean * h * t ** 1.6) + Z * (h * t) for t in ts]
        p.tube(pts, np.linspace(0.03, 0.018, 5), 4, "stem_brown" if rng.random_sample() < 0.5 else "stem_green")
        top = pts[-1]
        rise = math.radians(rng.uniform(38, 55) if young else rng.uniform(2, 24))
        U = out * math.cos(rise) + Z * math.sin(rise)
        R = nrm(np.cross(U, Z))
        p.card("bracken", top, R, U, (rng.uniform(0.45, 0.55) if young else rng.uniform(0.62, 0.95) * (0.75 + 0.1 * h)),
               nu=4, nv=4, bend=rng.uniform(0.25, 0.65),
               bend_dir=-1.0, droop=0.16, normal_fn=up_blend(0.35), twist=rng.uniform(-0.25, 0.25))
    ob = p.build("FernA_Fern")
    lib.add(root, ob, "Fern", "Plants", alpha="Transparency", backfaces=True,
            rgb=slot_rgb(L["Plants"], ["bracken"]))
    lib.finish(root, ground_tol=0.08)
    return root


def build_fern_sword(lib, L, rng):
    root = lib.begin("FernB", "Plant", ["Fern", "SwordFern", "Cover"],
                     "Sword fern: fountain rosette of arching single-pinnate fronds.", budget=900)
    p = Part(L["Plants"])
    nfr = 13
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(nfr):
        yaw = i * golden + rng.uniform(-0.2, 0.2)
        out = np.array([math.cos(yaw), math.sin(yaw), 0.0])
        young = i < 3
        elev = math.radians(rng.uniform(70, 82) if young else rng.uniform(48, 72))
        U = out * math.cos(elev) + Z * math.sin(elev)
        R = nrm(np.cross(U, Z))
        arch = rng.uniform(0.5, 0.8) if young else rng.uniform(0.9, 1.5)
        sl = "swordfern_b" if (young or rng.random_sample() < 0.3) else "swordfern_a"
        p.card(sl, out * 0.06 + np.array([0, 0, -0.04]), R, U, rng.uniform(0.82, 1.05) * (0.85 if young else 1.0),
               nu=2, nv=7, bend=arch, bend_dir=-1.0, bend_pow=1.3, fold=0.1, normal_fn=up_blend(0.45),
               twist=rng.uniform(-0.3, 0.3))
    ob = p.build("FernB_Fern")
    lib.add(root, ob, "Fern", "Plants", alpha="Transparency", backfaces=True,
            rgb=slot_rgb(L["Plants"], ["swordfern_a", "swordfern_b"]))
    lib.finish(root, ground_tol=0.08)
    return root


# =============================================================================================== reeds
def build_reeds(lib, L, rng):
    root = lib.begin("ReedsA", "Plant", ["Reeds", "Cattail", "Shore", "Marsh", "Cover"],
                     "Common reed and cattails for shores and the marsh (5-6.5 tall). Sink 0.3-1 into shallow water.",
                     budget=900)
    p = Part(L["Plants"])
    for k in range(7):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.9)
        base = np.array([math.cos(a) * r, math.sin(a) * r, -0.1])
        R, U = frame_yaw(rng.uniform(0, math.pi), rng.uniform(0.0, 0.12), np.array([math.cos(a), math.sin(a), 0]))
        p.card("reed", base, R, U, rng.uniform(0.86, 1.0), nu=1, nv=4, bend=rng.uniform(0.05, 0.25),
               bend_dir=rng.choice([-1.0, 1.0]), normal_fn=up_blend(0.5))
    for k in range(7):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.2, 1.1)
        base = np.array([math.cos(a) * r, math.sin(a) * r, -0.1])
        R, U = frame_yaw(rng.uniform(0, math.pi), rng.uniform(0.0, 0.15), np.array([math.cos(a), math.sin(a), 0]))
        p.card("cattail", base, R, U, rng.uniform(0.8, 1.0), nu=1, nv=4, bend=rng.uniform(0.05, 0.3),
               bend_dir=rng.choice([-1.0, 1.0]), normal_fn=up_blend(0.5))
    for k in range(5):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.1, 0.8)
        base = np.array([math.cos(a) * r, math.sin(a) * r, -0.1])
        h = rng.uniform(4.4, 5.4)
        lean = nrm(np.array([math.cos(a), math.sin(a), 0])) * rng.uniform(0.0, 0.25)
        ts = np.linspace(0, 1, 5)
        stem = [base + lean * t * t * h * 0.3 + Z * t * h for t in ts]
        p.tube(stem, np.linspace(0.026, 0.016, 5), 4, "stem_green", normal_fn=lambda c, o: nrm(o + Z * 0.4))
        d = nrm(stem[-1] - stem[-2])
        hb = stem[-1]
        head = [hb + d * t for t in np.linspace(0, 0.62, 3)]
        p.tube(head, [0.075, 0.085, 0.07], 6, "cattail_head", normal_fn=lambda c, o: nrm(o + Z * 0.3))
        spike = [head[-1], head[-1] + d * 0.32]
        p.tube(spike, [0.012, 0.004], 3, "stem_brown")
    ob = p.build("ReedsA_Reed")
    lib.add(root, ob, "Reed", "Plants", alpha="Transparency", backfaces=True,
            rgb=slot_rgb(L["Plants"], ["reed", "cattail"]))
    lib.finish(root, ground_tol=0.15)
    return root


# =============================================================================================== bushes
def ellipsoid_points(rng, n, rx, ry, rz, z0, zmin_frac=0.12, noise=None):
    """Points + outward normals on an ellipsoid shell (upper part), jittered by a noise function."""
    pts, nrms = [], []
    golden = math.pi * (3 - math.sqrt(5))
    i = 0
    while len(pts) < n and i < n * 4:
        i += 1
        u = 1.0 - 2.0 * rng.uniform(0, 1)
        if u < -0.25:
            continue
        a = rng.uniform(0, 2 * math.pi)
        s = math.sqrt(1 - u * u)
        d = np.array([s * math.cos(a), s * math.sin(a), u])
        r = 1.0 + (noise(d) if noise else 0.0)
        p = np.array([d[0] * rx * r, d[1] * ry * r, z0 + d[2] * rz * r])
        if p[2] < rz * zmin_frac:
            continue
        g = nrm(np.array([d[0] / rx, d[1] / ry, d[2] / rz]))
        pts.append(p)
        nrms.append(g)
    return np.array(pts), np.array(nrms)


def bush_core(part, rng, fill_slot, rx, ry, rz, z0, center, segs=14, rings=8, noise=None):
    """Closed blob under the cards so the bush hides what is behind it. Per-face islands on an opaque fill."""
    verts = {}
    for r in range(rings + 1):
        th = math.pi * r / rings
        for s in range(segs):
            ph = 2 * math.pi * s / segs
            d = np.array([math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)])
            k = 1.0 + (noise(d) if noise else 0.0)
            z = z0 + d[2] * rz * k
            taper = 1.0 - 0.32 * max(0.0, -d[2]) ** 1.5
            verts[(r, s)] = np.array([d[0] * rx * k * taper, d[1] * ry * k * taper, max(z, 0.02 if d[2] < 0 else z)])
    polys, nrms = [], []
    sn = sphere_normals(center, 0.85, 0.1)
    for r in range(rings):
        for s in range(segs):
            s2 = (s + 1) % segs
            q = [verts[(r, s)], verts[(r + 1, s)], verts[(r + 1, s2)], verts[(r, s2)]]
            if r == 0:
                q = [verts[(0, 0)], verts[(1, s)], verts[(1, s2)]]
            elif r == rings - 1:
                q = [verts[(r, s)], verts[(r + 1, 0)], verts[(r, s2)]]
            polys.append(q)
            nrms.append([sn(v, nrm(v - center)) for v in q])
    part.quad_islands(fill_slot, polys, nrms, rng)


def build_bush(lib, L, rng, kind):
    S = L["Shrubs"]
    if kind == "A":
        name, rx, ry, rz, ncards = "BushA", 3.45, 3.15, 4.1, 130
        slots, fill, scale_rng = ["evergreen_a", "evergreen_b"], "fill_evergreen", (1.25, 1.75)
        notes = "Dense evergreen shrub (small glossy leaves) that hides a crouching player; walk-through."
    elif kind == "B":
        name, rx, ry, rz, ncards = "BushB", 3.6, 3.2, 2.3, 100
        slots, fill, scale_rng = ["broadleaf_a", "broadleaf_b"], "fill_broadleaf", (1.1, 1.5)
        notes = "Low spreading broadleaf shrub; walk-through."
    else:
        name, rx, ry, rz, ncards = "BerryBush", 2.8, 2.6, 3.6, 90
        slots, fill, scale_rng = ["currant"], "fill_broadleaf", (1.05, 1.45)
        notes = ("Currant-like shrub with red berry clusters (forage cue). BerryBush_Berries is a separate part: "
                 "hide it (Transparency 1 / parent away) when picked.")
    root = lib.begin(name, "Bush", ["Bush", "Cover", "Hide"] + (["Forage", "Berries"] if kind == "C" else []),
                     notes, budget=2000)
    pn = tg.Perlin(rng.randint(1 << 30))
    noise = lambda d: 0.12 * float(pn.noise(d[0] * 1.7 + 3.1, d[1] * 1.7, d[2] * 1.7))
    p = Part(S)
    z0 = 0.0
    center = np.array([0.0, 0.0, rz * 0.38])
    bush_core(p, rng, fill, rx * 0.8, ry * 0.8, rz * 0.86, z0, center, noise=noise)
    pts, nrms = ellipsoid_points(rng, ncards, rx * 0.93, ry * 0.93, rz * 0.97, z0, 0.02, noise)
    sn = sphere_normals(center, 0.72, 0.12)
    for (q, g) in zip(pts, nrms):
        nfront = nrm(g + rng.normal(0, 0.35, 3))
        up_t = Z - nfront * np.dot(Z, nfront)
        if np.linalg.norm(up_t) < 1e-3:
            up_t = np.array([1.0, 0, 0])
        up_t = nrm(up_t)
        ang = rng.uniform(-0.8, 0.8)
        side = np.cross(up_t, nfront)
        U = nrm(up_t * math.cos(ang) + side * math.sin(ang))
        R = nrm(np.cross(U, nfront))
        sc = rng.uniform(*scale_rng)
        base = q - U * 0.35 * sc - g * 0.12
        if base[2] < 0.05:
            U = nrm(U + Z * 0.8)
            R = nrm(np.cross(U, nfront))
            base[2] = 0.05
        p.card(slots[rng.randint(len(slots))], base, R, U, sc, nu=1, nv=2, bend=rng.uniform(0.1, 0.45),
               bend_dir=-1.0, normal_fn=sn)
    ob = p.build(name + "_Leaves")
    lib.add(root, ob, "Leaves", "Shrubs", alpha="Transparency", backfaces=True, cast_shadow=True,
            tags=["HideSpot"], rgb=slot_rgb(S, slots + [fill], [1.0] * len(slots) + [0.6]))
    if kind == "C":
        b = Part(S)
        s = S["berry"]
        cx = (s["slot"][0] + s["slot"][2] / 2) / PAGE
        cy = (s["slot"][1] + s["slot"][3] / 2) / PAGE
        rad_uv = (s["slot"][2] / 2 - 4) / PAGE
        ico_v, ico_f = icosahedron()
        nclusters = 9
        cpts, cn = ellipsoid_points(rng, nclusters * 3, rx * 0.98, ry * 0.98, rz * 0.97, z0, 0.25, noise)
        order = rng.permutation(len(cpts))[:nclusters]
        count = 0
        for ci in order:
            c0 = cpts[ci] + cn[ci] * 0.1
            nb = rng.randint(4, 7)
            hang = nrm(np.array([rng.normal(0, 0.3), rng.normal(0, 0.3), -1.0]))
            for j in range(nb):
                r = rng.uniform(0.075, 0.095)
                c = c0 + hang * (j * 0.14) + cn[ci] * 0.05 * rng.uniform(-1, 1) + np.cross(hang, cn[ci]) * rng.normal(0, 0.05)
                V = c + ico_v * r
                th = np.arccos(np.clip(-ico_v[:, 2], -1, 1))         # angle from the bottom pole
                ph = np.arctan2(ico_v[:, 1], ico_v[:, 0])
                rr = rad_uv * th / math.pi
                UV = np.stack([cx + rr * np.cos(ph), cy + rr * np.sin(ph)], 1)
                b._add(V, ico_v, UV, ico_f, False)
                count += 1
        obb = b.build("BerryBush_Berries")
        lib.add(root, obb, "Berries", "Shrubs", alpha="Transparency", name="BerryBush_Berries",
                tags=["Forage", "HideWhenPicked"], rgb=slot_rgb(S, ["berry"]))
        lib._entry(root)["notes"] += " %d berries in %d clusters." % (count, nclusters)
    lib.finish(root, ground_tol=0.08)
    return root


def icosahedron():
    t = (1 + 5 ** 0.5) / 2
    v = np.array([[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
                  [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]], float)
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    return v, f


# =============================================================================================== sapling
def build_sapling(lib, L, rng):
    S = L["Shrubs"]
    root = lib.begin("SaplingBroadleaf", "Tree", ["Sapling", "Broadleaf"],
                     "Young beech-like broadleaf (~8.5 tall). Trunk collides (thin Hull); crown is walk-through.",
                     budget=2500)
    H = 7.6
    trunk = Part(S)
    ts = np.linspace(0, 1, 11)
    sway = rng.uniform(0, 2 * math.pi)
    pts = [np.array([0.18 * math.sin(t * 2.4 + sway) * t, 0.14 * math.cos(t * 1.9 + sway) * t, t * H]) for t in ts]
    radii = 0.14 * (1 - ts) ** 0.85 + 0.022
    radii[0] = 0.17
    trunk.tube(pts, radii, 7, "bark", mode="repeat", seg_studs=3.9)
    obt = trunk.build("SaplingBroadleaf_Trunk")
    crown = Part(S)
    center = np.array([0.0, 0.0, H * 0.66])
    sn = sphere_normals(center, 0.7, 0.15)
    nbr = 8
    tips = []
    for b in range(nbr):
        f = 0.3 + 0.62 * b / (nbr - 1)
        i = int(f * 10)
        p0 = pts[i]
        a = b * 2.4 + rng.uniform(-0.3, 0.3)
        out = np.array([math.cos(a), math.sin(a), 0.0])
        blen = (2.4 - 1.3 * f) * rng.uniform(0.85, 1.1)
        up = rng.uniform(0.45, 0.9)
        bp = [p0 + (out * math.cos(up) + Z * math.sin(up)) * blen * t + Z * (-0.15 * blen * t * t) for t in
              np.linspace(0, 1, 4)]
        crown.tube(bp, np.linspace(0.05 * (1.2 - f), 0.012, 4), 4, "bark", mode="repeat", seg_studs=3.9)
        tips.append((bp, out))
    # leaf sprays along branches and the leader
    for (bp, out) in tips + [([pts[7], pts[8], pts[9], pts[10]], nrm(pts[10] - pts[9]))]:
        nspray = 12
        for k in range(nspray):
            t = rng.uniform(0.25, 1.0)
            seg = min(int(t * (len(bp) - 1)), len(bp) - 2)
            q = bp[seg] + (bp[seg + 1] - bp[seg]) * (t * (len(bp) - 1) - seg)
            d = nrm(out + rng.normal(0, 0.45, 3) + Z * 0.15)
            U = d
            nfront = nrm(sn(q, Z) + rng.normal(0, 0.25, 3))
            nfront = nrm(nfront - U * np.dot(nfront, U))
            R = nrm(np.cross(U, nfront))
            crown.card(["beech_a", "beech_b"][rng.randint(2)], q, R, U, rng.uniform(0.95, 1.35), nu=1, nv=2,
                       bend=rng.uniform(0.15, 0.5), bend_dir=-1.0, normal_fn=sn)
    obc = crown.build("SaplingBroadleaf_Leaves")
    lib.add(root, obt, "Trunk", "Shrubs", collide=True, collision="Hull", cast_shadow=True, alpha="Overlay",
            rgb=slot_rgb(S, ["bark"]))
    lib.add(root, obc, "Leaves", "Shrubs", alpha="Transparency", backfaces=True, cast_shadow=True,
            rgb=slot_rgb(S, ["beech_a", "beech_b"]))
    lib.finish(root, ground_tol=0.08)
    return root


# =============================================================================================== mushrooms
def build_mushrooms(lib, L, rng):
    S = L["Shrubs"]
    root = lib.begin("MushroomsA", "Plant", ["Mushroom", "ForestFloor"],
                     "Cluster of tawny brown-capped mushrooms on a leaf-litter patch.", budget=900)
    p = Part(S)
    cap = S["mush_cap"]
    gills = S["mush_gills"]
    ccx, ccy = (cap["slot"][0] + cap["slot"][2] / 2) / PAGE, (cap["slot"][1] + cap["slot"][3] / 2) / PAGE
    gcx, gcy = (gills["slot"][0] + gills["slot"][2] / 2) / PAGE, (gills["slot"][1] + gills["slot"][3] / 2) / PAGE
    crad = 0.24 * cap["density"] / PAGE * 0.97
    # litter base (flat, slightly domed, single-sided)
    lit = S["litter"]
    lx0, ly0, lx1, ly1 = lit["rect"]
    gx = np.linspace(-0.85, 0.85, 5)
    gy = np.linspace(-0.75, 0.75, 5)
    V, UV, N, F = [], [], [], []
    for j, y in enumerate(gy):
        for i, x in enumerate(gx):
            V.append((x, y, 0.02 + 0.03 * (1 - x * x) * (1 - y * y)))
            UV.append(((lx0 + (lx1 - lx0) * (i / 4)) / PAGE, (ly0 + (ly1 - ly0) * (j / 4)) / PAGE))
            N.append(Z)
    for j in range(4):
        for i in range(4):
            a = j * 5 + i
            F.append((a, a + 1, a + 6, a + 5))
    p._add(np.array(V), np.array(N), np.array(UV), F, False)
    specs = [(0.21, 0.42, 0.0), (0.16, 0.34, 0.15), (0.12, 0.26, -0.2), (0.18, 0.48, 0.1), (0.09, 0.18, 0.3),
             (0.07, 0.12, 0.0), (0.13, 0.3, -0.35)]
    for k, (cr, h, tilt) in enumerate(specs):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.05, 0.55)
        base = np.array([math.cos(a) * r, math.sin(a) * r, 0.0])
        lean = nrm(Z + np.array([math.cos(a), math.sin(a), 0]) * (abs(tilt) + 0.08))
        top = base + lean * h
        srad = cr * rng.uniform(0.18, 0.24)
        stem = [base + lean * h * t for t in np.linspace(0, 1, 3)]
        p.tube(stem, [srad * 1.15, srad, srad * 0.9], 6, "mush_stem")
        segs = 9
        # cap profile: (radius fraction, height fraction above the cap base)
        prof = [(1.0, -0.05), (0.97, 0.18), (0.82, 0.42), (0.55, 0.62), (0.0, 0.7)]
        capV, capN, capUV = [], [], []
        e1 = nrm(np.cross(lean, np.array([1.0, 0.0, 0.0])))
        e2 = np.cross(lean, e1)
        ch = cr * (0.75 if k % 2 else 0.6)
        for (rf, hf) in prof:
            for s in range(segs + 1):
                ph = 2 * math.pi * s / segs
                o = e1 * math.cos(ph) + e2 * math.sin(ph)
                capV.append(top + o * cr * rf + lean * ch * hf)
                capN.append(nrm(o * rf + lean * (1.2 - rf)))
                capUV.append((ccx + crad * rf * math.cos(ph), ccy + crad * rf * math.sin(ph)))
        F = []
        for rI in range(len(prof) - 1):
            for s in range(segs):
                a0 = rI * (segs + 1) + s
                F.append((a0, a0 + 1, a0 + segs + 2, a0 + segs + 1))
        p._add(np.array(capV), np.array(capN), np.array(capUV), F, False)
        # gills: underside disc from the rim to the stem
        gV, gN, gUV = [], [], []
        for (rf, hf) in [(1.0, -0.05), (0.25, 0.08)]:
            for s in range(segs + 1):
                ph = 2 * math.pi * s / segs
                o = e1 * math.cos(ph) + e2 * math.sin(ph)
                gV.append(top + o * cr * rf + lean * ch * hf)
                gN.append(nrm(-lean + o * 0.3))
                gUV.append((gcx + crad * rf * math.cos(ph), gcy + crad * rf * math.sin(ph)))
        F = []
        for s in range(segs):
            F.append((s + segs + 1, s + segs + 2, s + 1, s))
        p._add(np.array(gV), np.array(gN), np.array(gUV), F, False)
    ob = p.build("MushroomsA_Mushroom")
    lib.add(root, ob, "Mushroom", "Shrubs", alpha="Transparency",
            rgb=slot_rgb(S, ["mush_cap", "litter"], [0.6, 0.4]))
    lib.finish(root, ground_tol=0.08)
    return root


# =============================================================================================== moss
def build_moss_patch(lib, L, rng):
    S = L["Shrubs"]
    root = lib.begin("MossPatch", "Plant", ["Moss", "Decal"],
                     "Low moss mat (4 x 2.2) plus two cushions for rocks, logs and ground. Single-sided, cut-out edge.",
                     budget=500)
    p = Part(S)
    pn = tg.Perlin(rng.randint(1 << 30))

    def mat(slot, cx, cy, w, h, dome, nx=9, ny=6):
        s = S[slot]
        x0, y0, x1, y1 = s["rect"]
        V, UV, N, F = [], [], [], []
        for j in range(ny + 1):
            for i in range(nx + 1):
                u, v = i / nx, j / ny
                x = (u - 0.5) * w
                y = (v - 0.5) * h
                rr = min(1.0, math.sqrt((2 * u - 1) ** 2 + (2 * v - 1) ** 2))
                z = dome * (1 - rr ** 2) + 0.03 * float(pn.noise(x * 1.3 + cx, y * 1.3 + cy, 0.5)) + 0.015
                V.append((cx + x, cy + y, z))
                UV.append(((x0 + (x1 - x0) * u) / PAGE, (y0 + (y1 - y0) * v) / PAGE))
        V = np.array(V)
        for j in range(ny):
            for i in range(nx):
                a = j * (nx + 1) + i
                F.append((a, a + 1, a + nx + 2, a + nx + 1))
        Nn = np.tile(Z, (len(V), 1))
        for j in range(ny + 1):
            for i in range(nx + 1):
                a = j * (nx + 1) + i
                du = V[j * (nx + 1) + min(i + 1, nx)] - V[j * (nx + 1) + max(i - 1, 0)]
                dv = V[min(j + 1, ny) * (nx + 1) + i] - V[max(j - 1, 0) * (nx + 1) + i]
                Nn[a] = nrm(np.cross(du, dv))
        p._add(V, Nn, np.array(UV), F, False)

    s = S["moss_mat"]
    w = (s["rect"][2] - s["rect"][0]) / s["density"]
    h = (s["rect"][3] - s["rect"][1]) / s["density"]
    mat("moss_mat", 0.0, 0.0, w, h, 0.16)
    for slot, cx, cy in (("moss_a", 1.9, 1.05), ("moss_b", -1.75, -1.0)):
        s = S[slot]
        w = (s["rect"][2] - s["rect"][0]) / s["density"] * 0.75
        h = (s["rect"][3] - s["rect"][1]) / s["density"] * 0.75
        mat(slot, cx, cy, w, h, 0.22, 6, 6)
    ob = p.build("MossPatch_Moss")
    lib.add(root, ob, "Moss", "Shrubs", alpha="Transparency", rgb=slot_rgb(S, ["moss_mat", "moss_a", "moss_b"]))
    lib.finish(root, ground_tol=0.08)
    return root


def build_all_flora(lib, L, log=print):
    roots = []
    R = lambda s: np.random.RandomState(s)
    roots.append(build_fern_bracken(lib, L, R(101)))
    roots.append(build_fern_sword(lib, L, R(102)))
    roots.append(build_bush(lib, L, R(103), "A"))
    roots.append(build_bush(lib, L, R(104), "B"))
    roots.append(build_bush(lib, L, R(105), "C"))
    roots.append(build_grass_tall(lib, L, R(106), "a"))
    roots.append(build_grass_tall(lib, L, R(107), "b"))
    roots.append(build_grass_forest(lib, L, R(108)))
    roots.append(build_reeds(lib, L, R(109)))
    roots.append(build_flowers(lib, L, R(110), "a"))
    roots.append(build_flowers(lib, L, R(111), "b"))
    roots.append(build_mushrooms(lib, L, R(112)))
    roots.append(build_sapling(lib, L, R(113)))
    roots.append(build_moss_patch(lib, L, R(114)))
    return roots
