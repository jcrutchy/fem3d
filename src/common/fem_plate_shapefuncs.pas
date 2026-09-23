unit fem_plate_shapefuncs;

{$mode objfpc}{$H+}

interface

uses
  fem_types, SysUtils;

const
  // 2x2 Gauss-Legendre quadrature on [-1,1]x[-1,1]: exact for the
  // isoparametric bilinear quad's stiffness integrand (which, for a
  // parallelogram element, reduces to degree <= 2 in each of xi, eta;
  // for a general non-parallelogram quad the Jacobian is only
  // bilinear and 2x2 is the conventional, not exact, choice -- same
  // tradeoff every mainstream FEA package makes for this element).
  GaussPt: Double = 0.5773502691896257; // 1/sqrt(3)
  NGaussPlate = 4;

type
  // One Gauss point's natural coordinates and integration weight.
  TGaussPoint = record
    Xi, Eta, Weight: Double;
  end;
  TGaussPointArray = array[0..NGaussPlate - 1] of TGaussPoint;

  // Shape function values N[1..4] and their natural-coordinate
  // derivatives dN/dXi[1..4], dN/dEta[1..4] at one (xi, eta), 1-based
  // to match TDenseMatrix/TElemMatrix's 1-based convention used
  // elsewhere in fem_elements.
  TQuadShapeFuncs = record
    N: array[1..4] of Double;
    dNdXi: array[1..4] of Double;
    dNdEta: array[1..4] of Double;
  end;

  // 8-node serendipity ("Q8") shape function values and natural
  // derivatives, 1-based. Nodes 1-4 are the same 4 corners as
  // TQuadShapeFuncs (same CCW order); nodes 5-8 are the midpoints of
  // edges 1-2, 2-3, 3-4, 4-1 respectively. Used only as the
  // interpolation basis for the DKQ plate-bending element's assumed
  // slope field (fem_elements.QuadBendingStiffnessLocal) -- the
  // element's geometry itself is still mapped with the plain bilinear
  // QuadShapeFuncsAt, matching every standard DKQ formulation (the
  // quadratic field describes the assumed rotations, not the shape).
  TQuad8ShapeFuncs = record
    N: array[1..8] of Double;
    dNdXi: array[1..8] of Double;
    dNdEta: array[1..8] of Double;
  end;

// The standard 2x2 Gauss rule, node numbering matching QuadShapeFuncsAt's
// corner order below (all weights are 1.0 for this rule; kept explicit
// per-point since fem_pcg and fem_eigen both keep their own "weights are
// data, not a hardcoded assumption" convention).
function QuadGaussPoints2x2: TGaussPointArray;

// 4-node bilinear ("Q4") quad shape functions and their natural
// derivatives at natural coordinates (xi, eta), each in [-1, 1].
// Corner order (standard isoparametric CCW numbering, matches every
// other 4-node-quad convention in the FEA literature):
//   node 1: (xi,eta) = (-1,-1)   node 2: (+1,-1)
//   node 4: (-1,+1)              node 3: (+1,+1)
// Callers (element nodes 1..4) must supply their 4 corners in this same
// CCW order -- fem_validate is responsible for catching a badly-ordered
// (self-intersecting) quad before it reaches here; this function does
// not check for that itself.
function QuadShapeFuncsAt(Xi, Eta: Double): TQuadShapeFuncs;

// 8-node serendipity shape functions and natural derivatives, same
// corner order as QuadShapeFuncsAt plus edge midpoints 5 (1-2), 6
// (2-3), 7 (3-4), 8 (4-1). Standard quadratic serendipity ("Q8")
// functions -- ported from a reference DKQ implementation, see
// fem_elements.QuadBendingStiffnessLocal for provenance.
function Quad8ShapeFuncsAt(Xi, Eta: Double): TQuad8ShapeFuncs;

implementation

function QuadGaussPoints2x2: TGaussPointArray;
begin
  Result[0].Xi := -GaussPt; Result[0].Eta := -GaussPt; Result[0].Weight := 1.0;
  Result[1].Xi :=  GaussPt; Result[1].Eta := -GaussPt; Result[1].Weight := 1.0;
  Result[2].Xi :=  GaussPt; Result[2].Eta :=  GaussPt; Result[2].Weight := 1.0;
  Result[3].Xi := -GaussPt; Result[3].Eta :=  GaussPt; Result[3].Weight := 1.0;
end;

function QuadShapeFuncsAt(Xi, Eta: Double): TQuadShapeFuncs;
begin
  // N_i = 1/4 * (1 + xi*xi_i) * (1 + eta*eta_i), the standard bilinear
  // isoparametric quad shape functions.
  Result.N[1] := 0.25 * (1 - Xi) * (1 - Eta);
  Result.N[2] := 0.25 * (1 + Xi) * (1 - Eta);
  Result.N[3] := 0.25 * (1 + Xi) * (1 + Eta);
  Result.N[4] := 0.25 * (1 - Xi) * (1 + Eta);

  Result.dNdXi[1] := -0.25 * (1 - Eta);
  Result.dNdXi[2] :=  0.25 * (1 - Eta);
  Result.dNdXi[3] :=  0.25 * (1 + Eta);
  Result.dNdXi[4] := -0.25 * (1 + Eta);

  Result.dNdEta[1] := -0.25 * (1 - Xi);
  Result.dNdEta[2] := -0.25 * (1 + Xi);
  Result.dNdEta[3] :=  0.25 * (1 + Xi);
  Result.dNdEta[4] :=  0.25 * (1 - Xi);
end;

function Quad8ShapeFuncsAt(Xi, Eta: Double): TQuad8ShapeFuncs;
begin
  Result.N[1] := -0.25 * (1 - Xi) * (1 - Eta) * (1 + Xi + Eta);
  Result.N[2] := -0.25 * (1 + Xi) * (1 - Eta) * (1 - Xi + Eta);
  Result.N[3] := -0.25 * (1 + Xi) * (1 + Eta) * (1 - Xi - Eta);
  Result.N[4] := -0.25 * (1 - Xi) * (1 + Eta) * (1 + Xi - Eta);
  Result.N[5] :=  0.5 * (1 - Xi * Xi) * (1 - Eta);
  Result.N[6] :=  0.5 * (1 + Xi) * (1 - Eta * Eta);
  Result.N[7] :=  0.5 * (1 - Xi * Xi) * (1 + Eta);
  Result.N[8] :=  0.5 * (1 - Xi) * (1 - Eta * Eta);

  Result.dNdXi[1] := 0.25 * (1 - Eta) * (2 * Xi + Eta);
  Result.dNdXi[2] := 0.25 * (1 - Eta) * (2 * Xi - Eta);
  Result.dNdXi[3] := 0.25 * (1 + Eta) * (2 * Xi + Eta);
  Result.dNdXi[4] := 0.25 * (1 + Eta) * (2 * Xi - Eta);
  Result.dNdXi[5] := -Xi * (1 - Eta);
  Result.dNdXi[6] :=  0.5 * (1 - Eta * Eta);
  Result.dNdXi[7] := -Xi * (1 + Eta);
  Result.dNdXi[8] := -0.5 * (1 - Eta * Eta);

  Result.dNdEta[1] := 0.25 * (1 - Xi) * (Xi + 2 * Eta);
  Result.dNdEta[2] := 0.25 * (1 + Xi) * (-Xi + 2 * Eta);
  Result.dNdEta[3] := 0.25 * (1 + Xi) * (Xi + 2 * Eta);
  Result.dNdEta[4] := 0.25 * (1 - Xi) * (-Xi + 2 * Eta);
  Result.dNdEta[5] := -0.5 * (1 - Xi * Xi);
  Result.dNdEta[6] := -(1 + Xi) * Eta;
  Result.dNdEta[7] :=  0.5 * (1 - Xi * Xi);
  Result.dNdEta[8] := -(1 - Xi) * Eta;
end;

end.
