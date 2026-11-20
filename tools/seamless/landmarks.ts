// Landmarks: places one zone's map draws whole, whatever the shares give
// (ownership.ts), and places a zone, or a continent's blank land paper, gives up.
//
// The shares keep each zone a few world units off its map's edge, so a zone never ends
// on its map's straight edge, and settle land both zones claim for the smaller one. Both
// cut what the maps draw near their edges: a town at the edge of its zone's map, a wall
// or a range of mountains on the border, a coast just inside the map. Nothing in the data
// tells those apart (a zone's explored-area piece is a broad rectangle, the land around
// included), so they're listed here, each measured on its zone's art.
//
// A landmark is a disc (its middle, 0..1 on its map, and its radius in world units) or a
// polygon (its corners, 0..1 on its map). Drawn whole, it's its zone's over any claim,
// fading out over `fade` world units past it (LANDMARK_FADE by default), and toward its
// map's edge over `edgeFade` world units from `edgeKeep` off it (LANDMARK_EDGE_FADE and
// LANDMARK_EDGE_KEEP by default, less where the art runs cleanly nearer the edge than the
// torn border): the torn border stays out. No smaller zone (drawn over it) fades over it.
// With `hide`, its zone isn't drawn there at all, so what's under it shows (the open sea
// past a coast); on a continent, its blank land paper isn't (where its coarse outline
// takes sea for land).
//
// Where two zones' landmarks overlap, the later one owns the overlap: keep their order.

import { smooth } from "./images";
import type { Rect } from "./world";

export type Landmark = {
    mapID: number;
    name: string;
    fade?: number;
    edgeKeep?: number;
    edgeFade?: number;
    hide?: boolean;
} & (
    | { x: number; y: number; radius: number }
    | { polygon: [x: number, y: number][] }
);

const LANDMARK_FADE = 2;
const LANDMARK_EDGE_KEEP = 1.5;
const LANDMARK_EDGE_FADE = 2;

export const LANDMARKS: Landmark[] = [
    // Alterac Mountains and Hillsbrad Foothills ------------------------------------------

    // Dalaran's crater and banner, at Alterac's west edge, its west and top in Silverpine
    // Forest's territory (the lake shore its map draws there): Silverpine's mountains and
    // shore ran through the crater.
    { mapID: 1416, name: "Dalaran", x: 0.175, y: 0.674, radius: 8 },
    // Alterac's foothills, down to its burnt border: Hillsbrad's map, smaller, took them, and
    // drew its blank parchment between the two zones' green. Clear of Alterac's label for
    // Hillsbrad (west) and of Tarren Mill (east of the road).
    {
        mapID: 1416,
        name: "Alterac's foothills",
        polygon: [
            [0.289, 0.65],
            [0.261, 0.778],
            [0.261, 0.883],
            [0.317, 0.901],
            [0.317, 1],
            [0.534, 1],
            [0.539, 0.65],
        ],
        fade: 1,
    },
    // Thoradin's Wall, Arathi Highlands' border with Hillsbrad: Arathi's from the wall's west
    // face (a band along it, from just past its ends). Hillsbrad's map, smaller, took the
    // wall, with a strip of its blank parchment east of it.
    {
        mapID: 1417,
        name: "Thoradin's Wall",
        polygon: [
            [0.267, 0.128],
            [0.116, 0.471],
            [0.236, 0.471],
            [0.387, 0.128],
        ],
        fade: 1,
    },

    // Thandol Span: Arathi Highlands and Wetlands ----------------------------------------

    // Arathi's coast and its end of the bridge, at its map's bottom edge, then Wetlands'
    // strait and its end of the bridge, at its map's top edge: the continent's blank paper
    // showed between the two coasts.
    {
        mapID: 1417,
        name: "Arathi's coast on Thandol Span's strait",
        polygon: [
            [0.249, 0.8],
            [0.249, 0.913],
            [0.858, 0.913],
            [0.858, 0.8],
        ],
        fade: 1,
    },
    {
        mapID: 1437,
        name: "Wetlands' side of Thandol Span's strait",
        polygon: [
            [0.33, 0],
            [0.33, 0.13],
            [0.868, 0.13],
            [0.868, 0],
        ],
        fade: 1,
    },
    // The strait's mouth, west of the bridge, which no zone draws.
    {
        mapID: 1415,
        name: "Thandol Span's strait, off Eastern Kingdoms' land",
        hide: true,
        polygon: [
            [0.474, 0.407],
            [0.474, 0.426],
            [0.531, 0.426],
            [0.531, 0.407],
        ],
    },

    // Wetlands' west coast ---------------------------------------------------------------

    // Menethil Harbor, the town on its island and its label, at Wetlands' west edge.
    { mapID: 1437, name: "Menethil Harbor", x: 0.11, y: 0.561, radius: 6.5 },
    // Past the delta's coast, its blank margin and painted sea: the open sea instead. And its
    // blank margin down its west edge, short of Menethil Harbor's label.
    {
        mapID: 1437,
        name: "Wetlands' top-left corner",
        hide: true,
        polygon: [
            [0, 0],
            [0.379, 0],
            [0.329, 0.052],
            [0.269, 0.087],
            [0.205, 0.127],
            [0.15, 0.177],
            [0.112, 0.228],
            [0.09, 0.292],
            [0.07, 0.389],
            [0.047, 0.45],
            [0.047, 0.565],
            [0.035, 0.575],
            [0.035, 0.61],
            [0.047, 0.62],
            [0.047, 1],
            [0, 1],
        ],
        fade: 1,
    },

    // Wetlands and Dun Morogh, north of Ironforge ----------------------------------------

    // The mountains between them, which neither territory claims (the open sea showed):
    // Wetlands' down to above its label for Dun Morogh, along its west coast, then Dun
    // Morogh's from below its label for Wetlands, Wetlands' map (drawn over) fading into them.
    {
        mapID: 1437,
        name: "Wetlands' mountains north of Ironforge",
        polygon: [
            [0.16, 0.555],
            [0.089, 0.668],
            [0.079, 0.79],
            [0.408, 0.79],
            [0.45, 0.871],
            [0.549, 0.871],
            [0.549, 0.555],
        ],
        fade: 1.5,
    },
    {
        mapID: 1426,
        name: "Dun Morogh's mountains north of Ironforge",
        polygon: [
            [0.511, 0.096],
            [0.511, 0.225],
            [0.906, 0.225],
            [0.906, 0.096],
        ],
        fade: 1,
    },

    // Redridge Mountains -----------------------------------------------------------------

    // Below its seam with Burning Steppes, down to its burnt borders: its west and south
    // ranges and its river's mouth, with blank parchment between it and its neighbours.
    // West, from past the shading inside its edge, later at the river, so Elwynn's river
    // shows up to Redridge's stream.
    {
        mapID: 1433,
        name: "Redridge Mountains",
        polygon: [
            [0.06, 0.2],
            [0.06, 0.83],
            [0.092, 0.846],
            [0.092, 0.93],
            [0.06, 0.95],
            [0.06, 1],
            [1, 1],
            [1, 0.2],
        ],
        fade: 1,
        edgeKeep: 1,
    },
    // Deadwind Pass' mountains below Redridge's southwest corner (not its blank margin west
    // of them, which covered Elwynn's river).
    {
        mapID: 1430,
        name: "Deadwind Pass' mountains below Redridge",
        polygon: [
            [0.44, 0],
            [0.3, 0.18],
            [0.3, 0.306],
            [0.66, 0.306],
            [0.66, 0],
        ],
        fade: 1,
        edgeKeep: 1,
    },
    // Elwynn's mountains and river up to its east edge, meeting Redridge's.
    {
        mapID: 1429,
        name: "Elwynn Forest's east side",
        polygon: [
            [0.8, 0.15],
            [0.8, 0.95],
            [1, 0.95],
            [1, 0.15],
        ],
        edgeKeep: 1,
    },
    // Swamp of Sorrows' rows of mountains below Redridge's south range (over its label for
    // Redridge).
    {
        mapID: 1435,
        name: "Swamp of Sorrows' mountains below Redridge",
        polygon: [
            [0, 0.16],
            [0, 0.32],
            [0.68, 0.32],
            [0.68, 0.16],
        ],
        fade: 1.5,
    },

    // Elwynn Forest, north of Stormwind -------------------------------------------------

    // No zone's map covers the sea north of Stormwind: Eastern Kingdoms' land paper filled it,
    // and Elwynn's share stopped short of its mountains. The coast is Elwynn's mountains east of
    // the city, up to its map's top edge, then the city; not its blank parchment above them
    // (west of the city, a few faint ridges on it).
    {
        mapID: 1429,
        name: "Elwynn Forest's mountains east of Stormwind",
        polygon: [
            [0.31, 0.2],
            [0.33, 0.15],
            [0.35, 0.11],
            [0.4, 0.07],
            [0.45, 0.04],
            [0.508, 0.03],
            [0.508, 0.2],
        ],
        fade: 1,
        edgeKeep: 1,
        edgeFade: 1,
    },
    {
        mapID: 1429,
        name: "Elwynn Forest above its mountains and Stormwind",
        hide: true,
        polygon: [
            [-0.03, -0.03],
            [0.508, -0.03],
            [0.508, 0.025],
            [0.45, 0.035],
            [0.4, 0.065],
            [0.35, 0.105],
            [0.33, 0.145],
            [0.31, 0.19],
            [-0.03, 0.15],
        ],
        fade: 1,
    },
    {
        mapID: 1415,
        name: "North of Stormwind, off Eastern Kingdoms' land",
        hide: true,
        polygon: [
            [0.398, 0.5964],
            [0.4663, 0.5964],
            [0.4652, 0.6641],
            [0.4486, 0.6724],
            [0.4185, 0.6772],
            [0.4138, 0.6964],
            [0.398, 0.6964],
        ],
        fade: 1.5,
    },

    // Elwynn Forest, Duskwood and Westfall -----------------------------------------------

    // The rivers are the seams: Elwynn down to the middle of its river east, Duskwood from it,
    // both from the middle of the river south. Westfall's map (drawn under them) owned the
    // land past that river, and drew its blank margin there.
    {
        mapID: 1429,
        name: "Elwynn Forest, down to its river",
        polygon: [
            [0.23, 0.719],
            [0.23, 0.941],
            [0.301, 0.941],
            [0.391, 0.912],
            [0.519, 0.873],
            [0.648, 0.854],
            [0.807, 0.854],
            [0.807, 0.719],
        ],
        fade: 1,
        edgeKeep: 1,
    },
    // (west: the river's middle, bending east as it goes south)
    {
        mapID: 1431,
        name: "Duskwood, up to Elwynn's river",
        polygon: [
            [0.032, 0.222],
            [0.118, 0.235],
            [0.234, 0.197],
            [0.4, 0.141],
            [0.565, 0.103],
            [0.565, 0.854],
            [0.181, 0.854],
            [0.144, 0.774],
            [0.082, 0.61],
            [0.055, 0.48],
        ],
        fade: 1,
        edgeKeep: 1,
    },
    // Westfall's ring of cliffs up to the river's mouth, at its map's top edge: its land faded
    // to parchment and its cliffs were cut. Not its blank margin past them: the open sea.
    {
        mapID: 1436,
        name: "Westfall's north coast",
        polygon: [
            [0.2495, 0.3743],
            [0.2994, 0.2545],
            [0.3293, 0.1796],
            [0.3593, 0.1272],
            [0.3992, 0.0928],
            [0.4391, 0.0749],
            [0.479, 0.0674],
            [0.519, 0.0644],
            [0.5589, 0.0674],
            [0.5888, 0.0823],
            [0.6138, 0.0599],
            [0.6387, 0.0599],
            [0.6387, 0.3743],
        ],
        fade: 1,
        edgeKeep: 1,
    },
    {
        mapID: 1415,
        name: "Off Westfall's north coast",
        hide: true,
        polygon: [
            [0.3955, 0.7008],
            [0.3955, 0.7351],
            [0.3981, 0.7351],
            [0.4083, 0.7309],
            [0.4235, 0.7293],
            [0.4247, 0.7271],
            [0.4247, 0.7008],
        ],
        fade: 1,
    },

    // Westfall and Stranglethorn Vale ----------------------------------------------------

    // The seam is in the mountains: Westfall's south range and its tower, east to the river's
    // middle, into its range's lowest rows, then Stranglethorn's north mountains (drawn under
    // it) from Westfall's coast east past the river, over Duskwood's label for Stranglethorn.
    // Westfall's tower and range faded into haze, its plain land below them a band of
    // parchment over Stranglethorn's mountains.
    {
        mapID: 1436,
        name: "Westfall's south range and tower",
        polygon: [
            [0.3787, 0.6053],
            [0.3787, 0.898],
            [0.529, 0.898],
            [0.6, 0.853],
            [0.699, 0.853],
            [0.775, 0.868],
            [0.783, 0.8441],
            [0.767, 0.7964],
            [0.7351, 0.7327],
            [0.7032, 0.669],
            [0.6872, 0.6053],
        ],
        fade: 1.5,
    },
    {
        mapID: 1434,
        name: "Stranglethorn Vale's north mountains",
        polygon: [
            [0.1238, 0],
            [0.1238, 0.1127],
            [0.4564, 0.1127],
            [0.4564, 0],
        ],
        fade: 1,
        edgeKeep: 1,
    },
    {
        mapID: 1436,
        name: "Westfall below its south range",
        hide: true,
        polygon: [
            [0.3293, 0.9356],
            [0.529, 0.9356],
            [0.5988, 0.8907],
            [0.6986, 0.8907],
            [0.7784, 0.8982],
            [0.7784, 1],
            [0.3293, 1],
        ],
        fade: 1,
    },

    // Darkshore and Ashenvale -------------------------------------------------------------

    // The Zoram Strand's north coast and its isle sit at Ashenvale's top edge: Darkshore's
    // faded bottom took them, then Ashenvale's blank parchment showed up to its mountains.
    // Darkshore's mountains, road and river down to Ashenvale's mountains, then Ashenvale's
    // (drawn over it) isle and coast.
    {
        mapID: 1439,
        name: "Darkshore down to Ashenvale's mountains",
        polygon: [
            [0.2688, 0.8167],
            [0.2688, 0.9129],
            [0.2902, 0.9289],
            [0.333, 0.9289],
            [0.3971, 0.9321],
            [0.4142, 0.9481],
            [0.4613, 0.9481],
            [0.4613, 0.8167],
        ],
        fade: 1.5,
    },
    { mapID: 1440, name: "The Zoram Strand's isle", x: 0.0658, y: 0.1321, radius: 1.9, fade: 0.6 },
    {
        mapID: 1440,
        name: "The Zoram Strand's north coast",
        polygon: [
            [0.0852, 0.103],
            [0.1022, 0.0921],
            [0.1338, 0.1066],
            [0.1338, 0.1794],
            [0.0852, 0.1794],
        ],
        fade: 1,
    },

    // Ashenvale and Stonetalon Mountains -------------------------------------------------

    // The coast is the mountains: Ashenvale's range south of the Zoram Strand, out to its
    // west tip, then Stonetalon's north mountains (drawn over it) from its map's top edge,
    // the two fading into each other. Ashenvale's share stopped halfway along the range, and
    // Stonetalon's top faded into Kalimdor's land paper.
    {
        mapID: 1440,
        name: "Ashenvale's range south of the Zoram Strand",
        polygon: [
            [0.025, 0.422],
            [0.034, 0.396],
            [0.041, 0.374],
            [0.072, 0.37],
            [0.095, 0.36],
            [0.111, 0.348],
            [0.143, 0.348],
            [0.143, 0.459],
            [0.085, 0.462],
            [0.025, 0.454],
        ],
        fade: 1,
    },
    {
        mapID: 1442,
        name: "Stonetalon Mountains' north mountains",
        polygon: [
            [0.182, 0.16],
            [0.205, 0.083],
            [0.245, 0.019],
            [0.262, 0],
            [0.451, 0],
            [0.451, 0.152],
        ],
        fade: 1.5,
        edgeKeep: 0.3,
        edgeFade: 0.7,
    },
    // West of Ashenvale's range, Stonetalon's mountains ended on its map's straight top edge:
    // a coast from the range's west tip down its west side instead.
    {
        mapID: 1442,
        name: "Stonetalon Mountains' top-left corner",
        hide: true,
        polygon: [
            [0.1188, -0.0288],
            [0.3344, -0.0288],
            [0.3344, 0.0021],
            [0.2564, 0.04],
            [0.1934, 0.1053],
            [0.1188, 0.1259],
        ],
        fade: 1.5,
    },
    // The sea west of them and of the Zoram Strand, which Kalimdor's land paper took for land.
    {
        mapID: 1414,
        name: "Off Ashenvale's and Stonetalon Mountains' coast",
        hide: true,
        polygon: [
            [0.3913, 0.3488],
            [0.4327, 0.3488],
            [0.4327, 0.3762],
            [0.4317, 0.3853],
            [0.4286, 0.3881],
            [0.4236, 0.3892],
            [0.4215, 0.3929],
            [0.4206, 0.4082],
            [0.405, 0.4104],
            [0.4005, 0.4196],
            [0.3982, 0.4355],
            [0.3913, 0.4355],
        ],
        fade: 1.5,
    },

    // Stonetalon Mountains and Desolace --------------------------------------------------

    // The seam is in the mountains: Stonetalon's south range, then Desolace's (drawn over it)
    // coast range and Nijel's Point, near its map's top edge. Stonetalon's blank parchment,
    // its label for Desolace on it, showed between them.
    {
        mapID: 1442,
        name: "Stonetalon Mountains' south range",
        polygon: [
            [0.29, 0.6951],
            [0.7139, 0.6951],
            [0.7139, 0.8584],
            [0.29, 0.8584],
        ],
        fade: 1.5,
    },
    {
        mapID: 1442,
        name: "Stonetalon Mountains' blank bottom-left, with its label for Desolace",
        hide: true,
        polygon: [
            [-0.008, 0.6951],
            [0.1616, 0.6951],
            [0.1616, 0.8412],
            [0.2842, 0.8498],
            [0.29, 1.0216],
            [-0.008, 1.0216],
        ],
        fade: 1,
    },
    {
        mapID: 1443,
        name: "Desolace's coast range",
        polygon: [
            [0.4288, 0.0542],
            [0.547, 0.0542],
            [0.547, 0.3062],
            [0.3728, 0.3062],
            [0.3728, 0.2689],
            [0.4226, 0.1476],
        ],
        fade: 1,
    },
    { mapID: 1443, name: "Nijel's Point", x: 0.6466, y: 0.1009, radius: 3, fade: 1.5 },
    // The sea off the seam, which Kalimdor's land paper took for land.
    {
        mapID: 1414,
        name: "Off Stonetalon Mountains' and Desolace's coast",
        hide: true,
        polygon: [
            [0.3791, 0.4951],
            [0.3966, 0.4951],
            [0.397, 0.5145],
            [0.3997, 0.5168],
            [0.3997, 0.5316],
            [0.3791, 0.5316],
        ],
        fade: 1.5,
    },
    // Desolace's label for the Veiled Sea, out at sea, longer in some languages.
    {
        mapID: 1443,
        name: "Desolace's label for the Veiled Sea",
        hide: true,
        polygon: [
            [0.2234, 0.142],
            [0.3541, 0.142],
            [0.3541, 0.2035],
            [0.2234, 0.2035],
        ],
        fade: 1,
    },

    // Desolace and Feralas ---------------------------------------------------------------

    // The seam is in the mountains, west of Shen'dralas: Desolace's (drawn over Feralas) south
    // range and its path, down to its map's torn bottom edge, then Feralas' north range from
    // its map's top edge, its road on from the path. The two maps' blank margins showed
    // between them, over Kalimdor's land paper, which also took the sea off them for land.
    {
        mapID: 1444,
        name: "Feralas' north range",
        polygon: [
            [0.3304, 0],
            [0.4794, 0],
            [0.4794, 0.084],
            [0.3304, 0.084],
        ],
        fade: 1.5,
        edgeKeep: 1,
        edgeFade: 1,
    },
    {
        mapID: 1443,
        name: "Desolace's south range",
        polygon: [
            [0.2171, 0.8183],
            [0.4917, 0.8183],
            [0.4917, 1],
            [0.2171, 1],
        ],
        fade: 1.5,
        edgeFade: 1,
    },
    {
        mapID: 1414,
        name: "Off Desolace's and Feralas' coast",
        hide: true,
        polygon: [
            [0.3517, 0.6056],
            [0.3753, 0.6056],
            [0.3753, 0.6398],
            [0.3517, 0.6398],
        ],
        fade: 1.5,
    },

    // Thousand Needles and Tanaris -------------------------------------------------------

    // The seam is the Shimmering Flats' cliffs: Tanaris' west range fades out into Thousand
    // Needles' land from Un'Goro Crater's rim, its east range is cut along its peaks up to the
    // coast, and Thousand Needles' (drawn over it) flats inside their cliffs and land east of
    // them reach the coast. Thousand Needles' blank parchment, south of its canyon, covered
    // Tanaris' ranges.
    // Tanaris' map draws its west range up to its top edge, and differently whether Zul'Farrak's
    // piece is explored or not: any line through it shows, so it fades out slowly.
    {
        mapID: 1446,
        name: "Tanaris' west range and Zul'Farrak",
        polygon: [
            [0.322, 0.075],
            [0.34, 0.066],
            [0.36, 0.07],
            [0.38, 0.06],
            [0.4, 0.055],
            [0.42, 0.062],
            [0.44, 0.056],
            [0.46, 0.062],
            [0.48, 0.07],
            [0.575, 0.07],
            [0.59, 0.1],
            [0.59, 0.239],
            [0.4108, 0.239],
            [0.4, 0.17],
            [0.3676, 0.1335],
            [0.3297, 0.0848],
        ],
        fade: 4,
        edgeKeep: 0.5,
    },
    {
        mapID: 1446,
        name: "Tanaris' east range",
        polygon: [
            [0.575, 0.06],
            [0.582, 0.043],
            [0.592, 0.038],
            [0.61, 0.038],
            [0.62, 0.032],
            [0.632, 0.028],
            [0.644, 0.019],
            [0.652, 0.019],
            [0.664, 0.028],
            [0.668, 0.024],
            [0.676, 0.024],
            [0.682, 0.045],
            [0.689, 0.08],
            [0.686, 0.11],
            [0.6811, 0.13],
            [0.6811, 0.239],
            [0.575, 0.239],
        ],
        fade: 4,
        edgeKeep: 0.8,
        edgeFade: 0.8,
    },
    {
        mapID: 1441,
        name: "The Shimmering Flats",
        polygon: [
            [0.6785, 0.6054],
            [0.895, 0.6054],
            [0.9102, 0.7581],
            [0.8975, 0.863],
            [0.8631, 0.9012],
            [0.8122, 0.9165],
            [0.7804, 0.9299],
            [0.7676, 0.9585],
            [0.7231, 0.9585],
            [0.6785, 0.9203],
            [0.6403, 0.8726],
            [0.634, 0.7962],
            [0.6467, 0.7199],
            [0.6722, 0.6435],
        ],
        fade: 1,
    },
    {
        mapID: 1441,
        name: "East of the Shimmering Flats, from Dustwallow Marsh to Tanaris' east range",
        polygon: [
            [0.88, 0.43],
            [1, 0.43],
            [1, 0.6788],
            [0.9925, 0.6851],
            [0.9737, 0.671],
            [0.9611, 0.671],
            [0.9423, 0.6851],
            [0.9235, 0.6914],
            [0.9078, 0.7008],
            [0.88, 0.7008],
        ],
        fade: 0.6,
        edgeKeep: 0.3,
        edgeFade: 0.3,
    },
];

/** A landmark placed on the world, in world units: its box (left, right, top, bottom, its
 * fade included), and how far a point is in it, 0 to 1 (with the fade toward its map's edge
 * unless it's hidden). */
export type PlacedLandmark = {
    landmark: Landmark;
    box: [left: number, right: number, top: number, bottom: number];
    alpha: (u: number, v: number) => number;
};

/** The landmark on its map's rect (normalized on the world), the world `unitsWide` by `unitsHigh`. */
export function placeLandmark(landmark: Landmark, rect: Rect, unitsWide: number, unitsHigh: number): PlacedLandmark {
    const [left, right, top, bottom] = rect.map((value, i) => value * (i < 2 ? unitsWide : unitsHigh));
    const at = (x: number, y: number): [number, number] => [left + x * (right - left), top + y * (bottom - top)];
    const fade = landmark.fade ?? LANDMARK_FADE;
    const edgeKeep = landmark.edgeKeep ?? LANDMARK_EDGE_KEEP;
    const edgeFade = landmark.edgeFade ?? LANDMARK_EDGE_FADE;
    // world units outside it (0 inside), and its box
    let outside: (u: number, v: number) => number;
    let box: [number, number, number, number];
    if ("polygon" in landmark) {
        const corners = landmark.polygon.map(([x, y]) => at(x, y));
        outside = (u, v) => (insidePolygon(corners, u, v) ? 0 : toPolygon(corners, u, v));
        const us = corners.map((corner) => corner[0]);
        const vs = corners.map((corner) => corner[1]);
        box = [Math.min(...us), Math.max(...us), Math.min(...vs), Math.max(...vs)];
    } else {
        const [u0, v0] = at(landmark.x, landmark.y);
        const radius = landmark.radius;
        outside = (u, v) => Math.max(0, Math.hypot(u - u0, v - v0) - radius);
        box = [u0 - radius, u0 + radius, v0 - radius, v0 + radius];
    }
    return {
        landmark,
        box: [box[0] - fade, box[1] + fade, box[2] - fade, box[3] + fade],
        alpha: (u, v) => {
            const alpha = smooth(1 - outside(u, v) / fade);
            if (landmark.hide) return alpha;
            const toEdge = Math.min(u - left, right - u, v - top, bottom - v);
            return alpha * smooth((toEdge - edgeKeep) / edgeFade);
        },
    };
}

/** Whether (u, v) is inside the polygon (even-odd). */
function insidePolygon(corners: [number, number][], u: number, v: number): boolean {
    let inside = false;
    for (let i = 0, j = corners.length - 1; i < corners.length; j = i++) {
        const [ui, vi] = corners[i];
        const [uj, vj] = corners[j];
        if (vi > v !== vj > v && u < ((uj - ui) * (v - vi)) / (vj - vi) + ui) inside = !inside;
    }
    return inside;
}

/** The distance from (u, v) to the polygon's outline. */
function toPolygon(corners: [number, number][], u: number, v: number): number {
    let nearest = Infinity;
    for (let i = 0, j = corners.length - 1; i < corners.length; j = i++) {
        const [ui, vi] = corners[i];
        const [uj, vj] = corners[j];
        const du = uj - ui;
        const dv = vj - vi;
        const t = Math.max(0, Math.min(1, ((u - ui) * du + (v - vi) * dv) / (du * du + dv * dv)));
        nearest = Math.min(nearest, Math.hypot(u - (ui + t * du), v - (vi + t * dv)));
    }
    return nearest;
}
