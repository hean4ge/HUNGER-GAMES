"""hills.py - the gentle rolling hills laid over Map 1's valley floor (the owner, 20 Nov 2026: "make the map slightly
hilly"). pack.py calls add_hills() after the water repairs, so the Height blob, Map1Regions.lua and every builder
(Map1.Terrain, Scatter, Loot, Water, Audit) read the same ground.

A deterministic value-noise field (three octaves, wavelengths 384, 192 and 96 studs, seed HILL_SEED) times an
amplitude that grows from the meadow to the valley sides, times a mask that is 0 wherever the ground must stay as
Blender made it:
  - the heart: the knoll, the deck, the plinth ring and its turf (r < HEART_KEEP), feathered out to HEART_FULL
  - water: every wet cell and WATER_KEEP studs round it (the lake, the stream, their banks and levels), feathered
  - the trails (Map1_Layout trails) and the paths slot: TRAIL_KEEP studs either side, feathered
  - every landmark of the layout (its items: the built sites too): its footprint radius (LANDMARK_RADII), feathered.
    A site with nothing built is only a point for the loot, which is seated from the new heights, so it takes the hills
  - the Edge, the Crest and Outside regions, and everything beyond EDGE_FROM (the cliff lip at r 1,752)
  - steep ground (the ridges, crags, cliffs and the peak): the hills fade out between SLOPE_FROM and SLOPE_TO degrees
Only cells with a mask over 0 change. The packer's water rules still hold: no cell within WATER_KEEP of water moves.
numpy only.
"""
import math

import numpy as np

N = 1376
CELL = 4
ORIGIN = -2752
UNIT = 32

HILL_SEED = 4820
OCTAVES = ((320.0, 1.0), (160.0, 0.45), (80.0, 0.15))  # (wavelength studs, weight)
AMP_MEADOW = 10.0  # studs: the noise's p99 maps to this on the open floor (crest to trough up to about 20)
AMP_SIDES = 17.0  # ... and to this near the valley sides
SIDES_FROM, SIDES_TO = 380.0, 1100.0  # radius over which the amplitude grows
HEART_KEEP, HEART_FULL = 205.0, 330.0
EDGE_FROM, EDGE_TO = 1560.0, 1680.0  # hills fade to nothing before the Edge's lip (r 1,752)
WATER_KEEP, WATER_FULL = 28.0, 84.0
TRAIL_KEEP, TRAIL_FULL = 7.0, 52.0
SLOPE_FROM, SLOPE_TO = 15.0, 27.0
KEEP_REGIONS = (8, 9, 10)  # Edge, Crest, Outside
PATH_SLOT = 5
# footprint radius (zero) and feather (studs past it) for a layout item by asset-name prefix
LANDMARK_RADII = (
    ("M1_Peak", 360.0, 80.0),
    ("M1_SunGlade", 48.0, 48.0),
    ("M1_CrimsonSpiral", 34.0, 44.0),
    ("M1_LoneTree", 22.0, 56.0),
    ("M1_HollyHedge", 12.0, 48.0),
    ("M1_Berm", 9.0, 52.0),
)
DEFAULT_ITEM = (14.0, 52.0)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def centres():
    return ORIGIN + CELL * (np.arange(N) + 0.5)


def value_noise(wavelength, rng):
    """Smooth value noise on the grid: random values on a lattice `wavelength` studs apart, quintic-blended."""
    span = N * CELL * 1.5  # the lattice is turned, so it must cover the grid's diagonal
    m = int(math.ceil(span / wavelength)) + 4
    lattice = rng.uniform(-1.0, 1.0, size=(m, m))
    off = rng.uniform(0.0, wavelength, size=2)  # a random phase, so the octaves' lattices do not line up
    turn = rng.uniform(0.0, math.pi / 2)  # and a random turn, so no lattice lines up with the grid or another's
    c = centres()
    X, Z = np.meshgrid(c, c)
    ca, sa = math.cos(turn), math.sin(turn)
    fx = (X * ca + Z * sa) / wavelength + m / 2 + off[0] / wavelength
    fz = (-X * sa + Z * ca) / wavelength + m / 2 + off[1] / wavelength
    ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
    tx, tz = fx - ix, fz - iz
    # A cubic B-spline through the lattice, not a quintic blend: the quintic is flat round every lattice node, which
    # left plateaus 100 studs wide whose surface sat on one voxel layer, and Roblox draws such a sheet of grass with a
    # near-empty top voxel pale and bare (seen on the first build, 20 Nov). The B-spline is curved everywhere.
    def weights(t):
        t2, t3 = t * t, t * t * t
        return ((1 - t) ** 3 / 6, (3 * t3 - 6 * t2 + 4) / 6, (-3 * t3 + 3 * t2 + 3 * t + 1) / 6, t3 / 6)
    wx, wz = weights(tx), weights(tz)
    out = np.zeros(fx.shape)
    for a in range(4):
        row = np.zeros(fx.shape)
        for b in range(4):
            row += wx[b] * lattice[iz + a - 1, ix + b - 1]
        out += wz[a] * row
    return out


def noise_field():
    rng = np.random.default_rng(HILL_SEED)
    total = np.zeros((N, N))
    for wavelength, weight in OCTAVES:
        total += weight * value_noise(wavelength, rng)
    total -= total.mean()
    return total / np.percentile(np.abs(total), 99)


def distance(seed, max_cells):
    """Approximate distance in studs from the True cells of `seed` (octagonal dilation), capped at max_cells."""
    dist = np.full(seed.shape, np.inf)
    dist[seed] = 0.0
    front = seed.copy()
    reached = seed.copy()
    for step in range(1, max_cells + 1):
        grown = front.copy()
        grown[1:, :] |= front[:-1, :]
        grown[:-1, :] |= front[1:, :]
        grown[:, 1:] |= front[:, :-1]
        grown[:, :-1] |= front[:, 1:]
        if step % 2 == 0:  # diagonals every other step: an octagon, close to a circle
            grown[1:, 1:] |= front[:-1, :-1]
            grown[1:, :-1] |= front[:-1, 1:]
            grown[:-1, 1:] |= front[1:, :-1]
            grown[:-1, :-1] |= front[1:, 1:]
        new = grown & ~reached
        if not new.any():
            break
        dist[new] = step * CELL
        reached |= new
        front = reached
    return dist


def segment_distance(points, X, Z):
    """Distance in studs from every cell to a polyline [(x, z)]."""
    best = np.full(X.shape, np.inf)
    for (ax, az), (bx, bz) in zip(points[:-1], points[1:]):
        ex, ez = bx - ax, bz - az
        l2 = ex * ex + ez * ez
        u = np.clip(((X - ax) * ex + (Z - az) * ez) / l2, 0.0, 1.0) if l2 > 0 else 0.0
        d = np.hypot(X - (ax + ex * u), Z - (az + ez * u))
        np.minimum(best, d, out=best)
    return best


def box_blur(a, rad):
    """Separable box blur of radius `rad` cells (edges clamped)."""
    k = 2 * rad + 1
    p = np.pad(a, rad, mode="edge")
    c = np.cumsum(np.pad(p, ((0, 0), (1, 0))), axis=1)
    p = (c[:, k:] - c[:, :-k]) / k
    c = np.cumsum(np.pad(p, ((1, 0), (0, 0))), axis=0)
    return (c[k:, :] - c[:-k, :]) / k


def hill_mask(H, W, material, region, layout):
    """0..1 per cell: how much of the hill field a cell takes. Returns (mask, parts) with each part for the log."""
    c = centres()
    X, Z = np.meshgrid(c, c)
    r = np.hypot(X, Z)
    parts = {}
    parts["heart"] = sstep(HEART_KEEP, HEART_FULL, r)
    parts["edge"] = 1.0 - sstep(EDGE_FROM, EDGE_TO, r)
    wet = W > 0
    parts["water"] = sstep(WATER_KEEP, WATER_FULL, distance(wet, int(WATER_FULL / CELL) + 2))
    keep_region = np.isin(region, KEEP_REGIONS)
    parts["regions"] = sstep(8.0, 64.0, distance(keep_region, 18))
    trail_d = distance(material == PATH_SLOT, int(TRAIL_FULL / CELL) + 2)
    for trail in layout.get("trails", []) or []:
        pts = [(p[0], p[2]) for p in trail]
        if len(pts) >= 2:
            trail_d = np.minimum(trail_d, segment_distance(pts, X, Z))
    parts["trails"] = sstep(TRAIL_KEEP, TRAIL_FULL, trail_d)
    items = np.ones((N, N))

    def disc(x, z, keep, full):
        """items = min(items, the feathered disc) inside the disc's box only"""
        c0 = max(0, int((x - full - ORIGIN) // CELL) - 1)
        c1 = min(N, int((x + full - ORIGIN) // CELL) + 2)
        r0 = max(0, int((z - full - ORIGIN) // CELL) - 1)
        r1 = min(N, int((z + full - ORIGIN) // CELL) + 2)
        if c0 >= c1 or r0 >= r1:
            return
        sub = sstep(keep, full, np.hypot(X[r0:r1, c0:c1] - x, Z[r0:r1, c0:c1] - z))
        np.minimum(items[r0:r1, c0:c1], sub, out=items[r0:r1, c0:c1])

    for it in layout.get("items", []) or []:
        name = str(it.get("asset", ""))
        x, _y, z = it["position"]
        if math.hypot(x, z) < HEART_KEEP - 40:
            continue  # inside the heart: already kept
        keep, feather = DEFAULT_ITEM
        for prefix, k, f in LANDMARK_RADII:
            if name.startswith(prefix):
                keep, feather = k, f
        disc(x, z, keep, keep + feather)
    parts["landmarks"] = items
    hs = H.astype(np.float64) / UNIT
    gz, gx = np.gradient(hs, float(CELL))
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    slope = box_blur(slope, 4)  # the slope of the neighbourhood, so a lone rock does not punch a hole in a hill
    # blurred again after the step: the fade in and out of steep ground spreads over about 70 studs, so the hills'
    # own slope never jumps where the ground under them changes from gentle to steep
    weight = 1.0 - sstep(SLOPE_FROM, SLOPE_TO, slope)
    parts["slope"] = box_blur(box_blur(weight, 8), 8)
    mask = np.ones((N, N))
    for v in parts.values():
        mask *= v
    return mask, parts


def add_hills(H, W, material, region, layout):
    """H (int64 raw units) plus the hills. Returns (H3, info)."""
    c = centres()
    X, Z = np.meshgrid(c, c)
    r = np.hypot(X, Z)
    amp = AMP_MEADOW + (AMP_SIDES - AMP_MEADOW) * sstep(SIDES_FROM, SIDES_TO, r)
    field = noise_field()
    mask, parts = hill_mask(H, W, material, region, layout)
    delta = np.rint(field * amp * mask * UNIT).astype(np.int64)
    H3 = np.clip(H + delta, 32, 65535)
    changed = H3 != H
    dstuds = (H3 - H) / UNIT
    info = {
        "seed": HILL_SEED,
        "octaves": [list(o) for o in OCTAVES],
        "amplitude": [AMP_MEADOW, AMP_SIDES],
        "cellsChanged": int(changed.sum()),
        "raisedMax": float(dstuds.max()),
        "loweredMax": float(-dstuds.min()),
        "meanAbsWhereChanged": float(np.abs(dstuds[changed]).mean()) if changed.any() else 0.0,
        "inPlay": int((changed & (r < 1800)).sum()),
    }
    return H3, info, mask
