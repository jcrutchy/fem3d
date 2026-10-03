unit fem_validate;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, Classes, SysUtils, Generics.Collections, Math;

// Returns a list of human-readable error strings. Empty list = valid model.
// Pure function: does not mutate Model, does not touch stdout/stderr.
function ValidateModel(const Model: TModel): TStringList;

const
  SupportedElementTypes: array[0..3] of string = ('truss', 'beam', 'shellq4', 'shellq8');

implementation

function IsSupportedElementType(const T: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(SupportedElementTypes) do
    if SupportedElementTypes[i] = T then
    begin
      Result := True;
      Exit;
    end;
end;

function NodesPerElementType(const T: string): Integer;
begin
  if (T = 'truss') or (T = 'beam') then Result := 2
  else if T = 'shellq4' then Result := 4
  else if T = 'shellq8' then Result := 8
  else Result := 0;
end;

function ValidateModel(const Model: TModel): TStringList;
var
  Errs: TStringList;
  NodeIdx, MatIdx, PropIdx, ElemIdx: TIntIntMap;
  NodeDofCounts: TIntArray;
  i, j, expectedNodes, nIdx, dofOff, matI, propI, fc, lc, c: Integer;
  el: TElement;
  prop: TProperty;
  comb: TCombination;
  hasConstraint, usesBeam: Boolean;
  refDx, refDy, refDz, refLen, cosAngle, ax, ay, az, aLen: Double;
  n1, n2: TNode;
  n3, n4: TNode;
  n5, n6, n7, n8: TNode;
  e1x, e1y, e1z, e2x, e2y, e2z, e1Len, e2Len, nx, ny, nz, nLen: Double;
  charLen, shortLen, d3x, d3y, d3z, outOfPlane: Double;
  FreedomCaseIds, LoadCaseIds: TStringList;
  SeenConstraintKeys: TStringList;
  constraintKey: string;

  // NaN and Infinity both fail every ordered comparison (NaN) or satisfy
  // a plain ">0" test (Infinity) -- so the existing "must be positive"
  // checks below do NOT reliably catch either one on their own (a NaN E
  // silently passes "E<=0" since NaN<=0 is false; an Infinite E silently
  // passes it too, since Infinity>0 is true). Call this alongside those
  // checks, not instead of them.
  procedure CheckFinite(v: Double; const Label_: string);
  begin
    if IsNan(v) then
      Errs.Add(Label_ + ' is NaN')
    else if IsInfinite(v) then
      Errs.Add(Label_ + ' is infinite');
  end;

  // Corner-orientation check for a quad shell (shellq4, or the 4 corner
  // nodes of a shellq8). Walking the corners 1-2-3-4, every corner must
  // turn the same way as corner 1 does -- and corner 1's turning
  // direction defines the element normal by construction (it is built
  // from nodes 1, 2, 4), so "the same way" needs no separate reference.
  // For each corner, s = sin(interior angle) = (edgeIn x edgeOut) . n /
  // (|edgeIn| |edgeOut|):
  //   s < 0  -> the corner turns the OTHER way: a concave (reentrant)
  //             corner, or a self-intersecting "bow-tie" (e.g. nodes
  //             listed 1-2-4-3 instead of around the perimeter);
  //   s ~ 0  -> three consecutive corners are collinear: degenerate.
  // Both drive the isoparametric Jacobian determinant to <= 0 at that
  // corner. The element routines do check detJ, but only at their Gauss
  // points (which don't include the corners) and only at assembly time,
  // where the failure surfaces as a solver error (exit 4) rather than
  // as the model-validation error (exit 3) it really is.
  //
  // Node WINDING (clockwise vs counter-clockwise) is deliberately NOT
  // checked: the element's local frame is built from its own node
  // ordering, so reversing the order just flips the local normal and
  // gives the same answer to machine precision (verified against
  // tests/regression/018_shellq4_clockwise_ok).
  procedure CheckQuadCornerOrientation(const el: TElement;
    const c1, c2, c3, c4: TNode; nxU, nyU, nzU: Double);
  var
    px, py, pz: array[0..3] of Double;
    k, kPrev, kNext: Integer;
    ax, ay, az, bx, by, bz, aLen, bLen, cx, cy, cz, sinAngle: Double;
  begin
    px[0] := c1.X; py[0] := c1.Y; pz[0] := c1.Z;
    px[1] := c2.X; py[1] := c2.Y; pz[1] := c2.Z;
    px[2] := c3.X; py[2] := c3.Y; pz[2] := c3.Z;
    px[3] := c4.X; py[3] := c4.Y; pz[3] := c4.Z;
    for k := 0 to 3 do
    begin
      kPrev := (k + 3) mod 4;
      kNext := (k + 1) mod 4;
      ax := px[k] - px[kPrev]; ay := py[k] - py[kPrev]; az := pz[k] - pz[kPrev];
      bx := px[kNext] - px[k]; by := py[kNext] - py[k]; bz := pz[kNext] - pz[k];
      aLen := Sqrt(ax*ax + ay*ay + az*az);
      bLen := Sqrt(bx*bx + by*by + bz*bz);
      if (aLen <= 0) or (bLen <= 0) then
      begin
        Errs.Add(Format('Element %d: %s has coincident corner nodes (zero-length edge at node %d)',
          [el.Id, el.ElementType, el.NodeIds[k]]));
        Exit;
      end;
      cx := ay*bz - az*by;
      cy := az*bx - ax*bz;
      cz := ax*by - ay*bx;
      sinAngle := (cx*nxU + cy*nyU + cz*nzU) / (aLen * bLen);
      if sinAngle < -1.0E-6 then
      begin
        Errs.Add(Format('Element %d: %s is not a valid convex quadrilateral -- corner node %d turns the opposite way to the rest of the element (a concave/reentrant corner, or nodes listed in a self-intersecting "bow-tie" order such as 1-2-4-3; list the four corners in order around the element''s perimeter)',
          [el.Id, el.ElementType, el.NodeIds[k]]));
        Exit;
      end
      else if sinAngle <= 1.0E-6 then
      begin
        Errs.Add(Format('Element %d: %s has a degenerate corner at node %d -- it and its two neighbouring corner nodes are (nearly) collinear',
          [el.Id, el.ElementType, el.NodeIds[k]]));
        Exit;
      end;
    end;
  end;

  // Shellq8-only: the Q8 formulation's isoparametric geometry mapping
  // (and, in turn, the exact-reproduction properties the element's
  // patch tests rely on) assumes each midside node sits at the exact
  // 3D midpoint of the two corner nodes on either side of it -- not
  // merely "roughly between them" or "in the right plane". This checks
  // the actual 3D distance from that exact midpoint against the same
  // charLen-relative tolerance the corner flatness check above uses,
  // which catches an out-of-plane midside node too (its true midpoint
  // is in-plane whenever both corners are, so any out-of-plane offset
  // shows up as nonzero distance here without a separate check).
  procedure CheckQ8MidsideNode(elId, midNodeId: Integer;
    const cornerA, cornerB, mid: TNode; charLenLocal: Double);
  var
    trueMidX, trueMidY, trueMidZ, offX, offY, offZ, offDist: Double;
  begin
    trueMidX := 0.5 * (cornerA.X + cornerB.X);
    trueMidY := 0.5 * (cornerA.Y + cornerB.Y);
    trueMidZ := 0.5 * (cornerA.Z + cornerB.Z);
    offX := mid.X - trueMidX; offY := mid.Y - trueMidY; offZ := mid.Z - trueMidZ;
    offDist := Sqrt(offX*offX + offY*offY + offZ*offZ);
    if offDist > 0.01 * charLenLocal then
      Errs.Add(Format('Element %d: shellq8 midside node %d is %.4g%% of the element''s characteristic edge length away from the exact midpoint of its edge (the Q8 formulation requires exact edge midpoints)',
        [elId, midNodeId, 100.0*offDist/charLenLocal]));
  end;

begin
  Errs := TStringList.Create;

  // --- nodes ---
  if Length(Model.Nodes) = 0 then
    Errs.Add('Model has no nodes');

  NodeIdx := IndexNodes(Model);
  if NodeIdx.Count <> Length(Model.Nodes) then
    Errs.Add('Duplicate node ids found');
  for i := 0 to High(Model.Nodes) do
  begin
    CheckFinite(Model.Nodes[i].X, Format('Node %d: x', [Model.Nodes[i].Id]));
    CheckFinite(Model.Nodes[i].Y, Format('Node %d: y', [Model.Nodes[i].Id]));
    CheckFinite(Model.Nodes[i].Z, Format('Node %d: z', [Model.Nodes[i].Id]));
  end;

  // --- materials ---
  MatIdx := IndexMaterials(Model);
  if MatIdx.Count <> Length(Model.Materials) then
    Errs.Add('Duplicate material ids found');
  for i := 0 to High(Model.Materials) do
  begin
    CheckFinite(Model.Materials[i].E, Format('Material %d: E', [Model.Materials[i].Id]));
    if Model.Materials[i].HasNu then
      CheckFinite(Model.Materials[i].Nu, Format('Material %d: nu', [Model.Materials[i].Id]));
    if Model.Materials[i].HasRho then
      CheckFinite(Model.Materials[i].Rho, Format('Material %d: rho', [Model.Materials[i].Id]));
    if Model.Materials[i].E <= 0 then
      Errs.Add(Format('Material %d: E must be positive', [Model.Materials[i].Id]));
    if Model.Materials[i].HasNu and ((Model.Materials[i].Nu <= -1.0) or (Model.Materials[i].Nu >= 0.5)) then
      Errs.Add(Format('Material %d: nu (Poisson''s ratio) must be in (-1, 0.5), got %g',
        [Model.Materials[i].Id, Model.Materials[i].Nu]));
    if Model.Materials[i].HasRho and (Model.Materials[i].Rho <= 0) then
      Errs.Add(Format('Material %d: rho (density) must be positive, got %g',
        [Model.Materials[i].Id, Model.Materials[i].Rho]));
  end;

  // --- properties ---
  PropIdx := IndexProperties(Model);
  if PropIdx.Count <> Length(Model.Properties) then
    Errs.Add('Duplicate property ids found');
  for i := 0 to High(Model.Properties) do
  begin
    prop := Model.Properties[i];
    if not IsSupportedElementType(prop.ElementType) then
      Errs.Add(Format('Property %d: unsupported element type "%s"', [prop.Id, prop.ElementType]))
    else
    begin
      if (prop.ElementType = 'shellq4') or (prop.ElementType = 'shellq8') then
      begin
        CheckFinite(prop.Thickness, Format('Property %d: thickness', [prop.Id]));
        if prop.Thickness <= 0 then
          Errs.Add(Format('Property %d: thickness must be positive for a %s', [prop.Id, prop.ElementType]));
        if MatIdx.TryGetValue(prop.MaterialId, matI) and not Model.Materials[matI].HasNu then
          Errs.Add(Format('Property %d: %s requires its material (%d) to specify nu (Poisson''s ratio)',
            [prop.Id, prop.ElementType, prop.MaterialId]));
      end
      else
      begin
        CheckFinite(prop.Area, Format('Property %d: area', [prop.Id]));
        if prop.Area <= 0 then
          Errs.Add(Format('Property %d: area must be positive', [prop.Id]));
        if prop.ElementType = 'beam' then
        begin
          CheckFinite(prop.Iy, Format('Property %d: Iy', [prop.Id]));
          CheckFinite(prop.Iz, Format('Property %d: Iz', [prop.Id]));
          CheckFinite(prop.J, Format('Property %d: J', [prop.Id]));
          if prop.Iy <= 0 then
            Errs.Add(Format('Property %d: Iy must be positive for a beam', [prop.Id]));
          if prop.Iz <= 0 then
            Errs.Add(Format('Property %d: Iz must be positive for a beam', [prop.Id]));
          if prop.J <= 0 then
            Errs.Add(Format('Property %d: J (torsion constant) must be positive for a beam', [prop.Id]));
          CheckFinite(prop.Cy, Format('Property %d: Cy', [prop.Id]));
          CheckFinite(prop.Cz, Format('Property %d: Cz', [prop.Id]));
          CheckFinite(prop.Rt, Format('Property %d: Rt', [prop.Id]));
          if prop.Cy < 0 then
            Errs.Add(Format('Property %d: Cy (extreme-fibre distance) must not be negative', [prop.Id]));
          if prop.Cz < 0 then
            Errs.Add(Format('Property %d: Cz (extreme-fibre distance) must not be negative', [prop.Id]));
          if prop.Rt < 0 then
            Errs.Add(Format('Property %d: Rt (torsional shear radius) must not be negative', [prop.Id]));
          if (prop.Cy > 0) <> (prop.Cz > 0) then
            Errs.Add(Format('Property %d: Cy and Cz (extreme-fibre distances) must be given together -- or both omitted for axial-only beam stresses', [prop.Id]));
          if MatIdx.TryGetValue(prop.MaterialId, matI) and not Model.Materials[matI].HasNu then
            Errs.Add(Format('Property %d: beam requires its material (%d) to specify nu (Poisson''s ratio), used to derive the shear modulus G',
              [prop.Id, prop.MaterialId]));
        end;
      end;
    end;
    if not MatIdx.ContainsKey(prop.MaterialId) then
      Errs.Add(Format('Property %d: references unknown material %d', [prop.Id, prop.MaterialId]));
  end;

  // --- elements ---
  ElemIdx := IndexElements(Model);
  if ElemIdx.Count <> Length(Model.Elements) then
    Errs.Add('Duplicate element ids found');
  usesBeam := False;
  for i := 0 to High(Model.Elements) do
  begin
    el := Model.Elements[i];
    if not IsSupportedElementType(el.ElementType) then
      Errs.Add(Format('Element %d: unsupported element type "%s"', [el.Id, el.ElementType]))
    else
    begin
      expectedNodes := NodesPerElementType(el.ElementType);
      if Length(el.NodeIds) <> expectedNodes then
        Errs.Add(Format('Element %d: type "%s" requires %d node(s), got %d',
          [el.Id, el.ElementType, expectedNodes, Length(el.NodeIds)]));
      if el.ElementType = 'beam' then usesBeam := True;
    end;
    for j := 0 to High(el.NodeIds) do
      if not NodeIdx.ContainsKey(el.NodeIds[j]) then
        Errs.Add(Format('Element %d: references unknown node %d', [el.Id, el.NodeIds[j]]));
    if not PropIdx.ContainsKey(el.PropertyId) then
      Errs.Add(Format('Element %d: references unknown property %d', [el.Id, el.PropertyId]))
    else if PropIdx.TryGetValue(el.PropertyId, propI)
       and (Model.Properties[propI].ElementType <> el.ElementType)
       and IsSupportedElementType(el.ElementType) then
      // Both types individually valid (or the "unsupported type" error above
      // already fired) but they don't match -- e.g. a beam element pointing
      // at a shellq4 property. Validating the property alone (area/Iy/Iz/J
      // vs. thickness) is not enough: ElementStiffnessFor dispatches on the
      // ELEMENT's type, so a mismatch here means whichever formulation runs
      // reads fields that were never validated for that formulation (a beam
      // reading an unvalidated, possibly-zero Area from a shellq4 property,
      // for instance) -- silently wrong, not rejected.
      Errs.Add(Format('Element %d: type "%s" does not match its property %d''s type "%s"',
        [el.Id, el.ElementType, el.PropertyId, Model.Properties[propI].ElementType]));

    // Shellq4 flatness: QuadShellStiffness3D builds its local plane from
    // nodes 1, 2, 4 (edges 1-2 and 1-4) and assumes node 3 lies in it --
    // a genuinely warped (non-planar) quad isn't representable by this
    // flat-shell formulation, so catch it here with an actionable message
    // rather than let it silently degrade accuracy or surface later as an
    // opaque assembly-time exception for a badly degenerate case.
    if (el.ElementType = 'shellq4') and (Length(el.NodeIds) = 4)
       and NodeIdx.ContainsKey(el.NodeIds[0]) and NodeIdx.ContainsKey(el.NodeIds[1])
       and NodeIdx.ContainsKey(el.NodeIds[2]) and NodeIdx.ContainsKey(el.NodeIds[3]) then
    begin
      n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
      n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
      n3 := Model.Nodes[NodeIdx[el.NodeIds[2]]];
      n4 := Model.Nodes[NodeIdx[el.NodeIds[3]]];
      e1x := n2.X-n1.X; e1y := n2.Y-n1.Y; e1z := n2.Z-n1.Z;
      e2x := n4.X-n1.X; e2y := n4.Y-n1.Y; e2z := n4.Z-n1.Z;
      e1Len := Sqrt(e1x*e1x + e1y*e1y + e1z*e1z);
      e2Len := Sqrt(e2x*e2x + e2y*e2y + e2z*e2z);
      if e1Len <= 0 then
        Errs.Add(Format('Element %d: shellq4 nodes 1 and 2 coincide (zero-length edge)', [el.Id]))
      else if e2Len <= 0 then
        Errs.Add(Format('Element %d: shellq4 nodes 1 and 4 coincide (zero-length edge)', [el.Id]))
      else
      begin
        // normal = edge1 x edge2 (unnormalized); zero => nodes 1,2,4 collinear
        nx := e1y*e2z - e1z*e2y;
        ny := e1z*e2x - e1x*e2z;
        nz := e1x*e2y - e1y*e2x;
        nLen := Sqrt(nx*nx + ny*ny + nz*nz);
        if nLen <= 0 then
          Errs.Add(Format('Element %d: shellq4 nodes 1, 2, and 4 are collinear (degenerate quad)', [el.Id]))
        else
        begin
          // signed distance of node 3 from the plane through node1 with
          // normal (nx,ny,nz)/nLen, relative to the SHORTER of the two edges
          // off node 1, so the tolerance scales with element size rather than
          // being an absolute unit. The shorter edge is the right yardstick:
          // a warp that is tiny against a long edge can still be a large
          // fraction of a narrow element's width (a 1 m x 5 mm strip with node
          // 3 lifted 5 mm is a badly twisted element, yet only 0.5% of its
          // length). Measuring against the longer edge let those through.
          charLen := e1Len;
          if e2Len < charLen then charLen := e2Len;
          d3x := n3.X-n1.X; d3y := n3.Y-n1.Y; d3z := n3.Z-n1.Z;
          outOfPlane := Abs((d3x*nx + d3y*ny + d3z*nz) / nLen);
          if outOfPlane > 0.01 * charLen then
            Errs.Add(Format('Element %d: shellq4 is not flat -- node %d is %.4g%% of the element''s shorter edge length out of the plane through nodes %d, %d, %d',
              [el.Id, el.NodeIds[2], 100.0*outOfPlane/charLen, el.NodeIds[0], el.NodeIds[1], el.NodeIds[3]]))
          else
            CheckQuadCornerOrientation(el, n1, n2, n3, n4, nx/nLen, ny/nLen, nz/nLen);
        end;
      end;
    end;

    // Shellq8 flatness + midside placement: same corner-flatness logic
    // as shellq4 (local plane from nodes 1, 2, 4; node 3 must lie in
    // it), PLUS each midside node (5-8) must sit at the exact midpoint
    // of its edge -- see CheckQ8MidsideNode's comment for why.
    if (el.ElementType = 'shellq8') and (Length(el.NodeIds) = 8)
       and NodeIdx.ContainsKey(el.NodeIds[0]) and NodeIdx.ContainsKey(el.NodeIds[1])
       and NodeIdx.ContainsKey(el.NodeIds[2]) and NodeIdx.ContainsKey(el.NodeIds[3])
       and NodeIdx.ContainsKey(el.NodeIds[4]) and NodeIdx.ContainsKey(el.NodeIds[5])
       and NodeIdx.ContainsKey(el.NodeIds[6]) and NodeIdx.ContainsKey(el.NodeIds[7]) then
    begin
      n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
      n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
      n3 := Model.Nodes[NodeIdx[el.NodeIds[2]]];
      n4 := Model.Nodes[NodeIdx[el.NodeIds[3]]];
      n5 := Model.Nodes[NodeIdx[el.NodeIds[4]]];
      n6 := Model.Nodes[NodeIdx[el.NodeIds[5]]];
      n7 := Model.Nodes[NodeIdx[el.NodeIds[6]]];
      n8 := Model.Nodes[NodeIdx[el.NodeIds[7]]];
      e1x := n2.X-n1.X; e1y := n2.Y-n1.Y; e1z := n2.Z-n1.Z;
      e2x := n4.X-n1.X; e2y := n4.Y-n1.Y; e2z := n4.Z-n1.Z;
      e1Len := Sqrt(e1x*e1x + e1y*e1y + e1z*e1z);
      e2Len := Sqrt(e2x*e2x + e2y*e2y + e2z*e2z);
      if e1Len <= 0 then
        Errs.Add(Format('Element %d: shellq8 nodes 1 and 2 coincide (zero-length edge)', [el.Id]))
      else if e2Len <= 0 then
        Errs.Add(Format('Element %d: shellq8 nodes 1 and 4 coincide (zero-length edge)', [el.Id]))
      else
      begin
        nx := e1y*e2z - e1z*e2y;
        ny := e1z*e2x - e1x*e2z;
        nz := e1x*e2y - e1y*e2x;
        nLen := Sqrt(nx*nx + ny*ny + nz*nz);
        if nLen <= 0 then
          Errs.Add(Format('Element %d: shellq8 nodes 1, 2, and 4 are collinear (degenerate quad)', [el.Id]))
        else
        begin
          // flatness is measured against the shorter edge (see the shellq4 check
          // above); the midside-node position checks below keep the longer-edge
          // scale they were written against.
          charLen := e1Len;
          if e2Len > charLen then charLen := e2Len;
          shortLen := e1Len;
          if e2Len < shortLen then shortLen := e2Len;
          d3x := n3.X-n1.X; d3y := n3.Y-n1.Y; d3z := n3.Z-n1.Z;
          outOfPlane := Abs((d3x*nx + d3y*ny + d3z*nz) / nLen);
          if outOfPlane > 0.01 * shortLen then
            Errs.Add(Format('Element %d: shellq8 is not flat -- corner node %d is %.4g%% of the element''s shorter edge length out of the plane through nodes %d, %d, %d',
              [el.Id, el.NodeIds[2], 100.0*outOfPlane/shortLen, el.NodeIds[0], el.NodeIds[1], el.NodeIds[3]]))
          else
          begin
            CheckQuadCornerOrientation(el, n1, n2, n3, n4, nx/nLen, ny/nLen, nz/nLen);
            CheckQ8MidsideNode(el.Id, el.NodeIds[4], n1, n2, n5, charLen);
            CheckQ8MidsideNode(el.Id, el.NodeIds[5], n2, n3, n6, charLen);
            CheckQ8MidsideNode(el.Id, el.NodeIds[6], n3, n4, n7, charLen);
            CheckQ8MidsideNode(el.Id, el.NodeIds[7], n4, n1, n8, charLen);
          end;
        end;
      end;
    end;

    // Beam orientation: an explicit refVec (or, if none given, global Z /
    // falling back to X) must not be (near-)parallel to the beam axis --
    // that's degenerate, there'd be no way to fix the beam's roll.
    if (el.ElementType = 'beam') and (Length(el.NodeIds) = 2)
       and NodeIdx.ContainsKey(el.NodeIds[0]) and NodeIdx.ContainsKey(el.NodeIds[1]) then
    begin
      n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
      n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
      ax := n2.X - n1.X; ay := n2.Y - n1.Y; az := n2.Z - n1.Z;
      aLen := Sqrt(ax * ax + ay * ay + az * az);
      if aLen > 0 then
      begin
        if el.HasRefVec then
        begin
          refDx := el.RefVec[0]; refDy := el.RefVec[1]; refDz := el.RefVec[2];
          if (refDx = 0) and (refDy = 0) and (refDz = 0) then
            Errs.Add(Format('Element %d: refVec must not be the zero vector', [el.Id]))
          else
          begin
            refLen := Sqrt(refDx * refDx + refDy * refDy + refDz * refDz);
            cosAngle := Abs((ax * refDx + ay * refDy + az * refDz) / (aLen * refLen));
            if cosAngle > 0.999 then
              Errs.Add(Format('Element %d: refVec is (near-)parallel to the beam axis -- cannot fix its roll orientation', [el.Id]));
          end;
        end;
      end;
    end;
  end;

  // --- per-node dof counts (needs element types/refs above, but tolerates errors) ---
  NodeDofCounts := ComputeNodeDofCounts(Model, NodeIdx);

  // --- freedom cases ---
  if Length(Model.FreedomCases) = 0 then
    Errs.Add('Model has no freedom cases'); // the loader always produces at least one; this would mean a bug upstream
  FreedomCaseIds := TStringList.Create;
  FreedomCaseIds.Sorted := True;
  FreedomCaseIds.Duplicates := dupIgnore;
  for fc := 0 to High(Model.FreedomCases) do
  begin
    if Model.FreedomCases[fc].Id = '' then
      Errs.Add(Format('Freedom case %d: missing "id"', [fc]));
    if FreedomCaseIds.IndexOf(Model.FreedomCases[fc].Id) >= 0 then
      Errs.Add(Format('Duplicate freedom case id "%s"', [Model.FreedomCases[fc].Id]))
    else
      FreedomCaseIds.Add(Model.FreedomCases[fc].Id);

    hasConstraint := Length(Model.FreedomCases[fc].Constraints) > 0;
    SeenConstraintKeys := TStringList.Create;
    SeenConstraintKeys.Sorted := True;
    SeenConstraintKeys.Duplicates := dupIgnore;
    for i := 0 to High(Model.FreedomCases[fc].Constraints) do
    begin
      dofOff := DofOffset(Model.FreedomCases[fc].Constraints[i].Dof);
      CheckFinite(Model.FreedomCases[fc].Constraints[i].Value,
        Format('Freedom case "%s", constraint %d: value', [Model.FreedomCases[fc].Id, i]));
      if not NodeIdx.TryGetValue(Model.FreedomCases[fc].Constraints[i].NodeId, nIdx) then
        Errs.Add(Format('Freedom case "%s", constraint %d: references unknown node %d',
          [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].NodeId]))
      else if dofOff >= 0 then
      begin
        if dofOff >= NodeDofCounts[nIdx] then
          Errs.Add(Format('Freedom case "%s", constraint %d: dof "%s" is rotational, but node %d has no rotational dof (not connected to any beam element)',
            [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].Dof, Model.FreedomCases[fc].Constraints[i].NodeId]));
        // Duplicate (node,dof) constraint within this freedom case: the
        // loader just keeps whichever wins last in fem_dofmap.BuildDofMap,
        // silently -- two constraints on the same dof (even if identical)
        // almost always means a model-generation bug, so this is a hard
        // error, not a "last one wins" convenience.
        constraintKey := Format('%d:%d', [Model.FreedomCases[fc].Constraints[i].NodeId, dofOff]);
        if SeenConstraintKeys.IndexOf(constraintKey) >= 0 then
          Errs.Add(Format('Freedom case "%s": duplicate constraint on node %d, dof "%s"',
            [Model.FreedomCases[fc].Id, Model.FreedomCases[fc].Constraints[i].NodeId,
             Model.FreedomCases[fc].Constraints[i].Dof]))
        else
          SeenConstraintKeys.Add(constraintKey);
      end;
      if dofOff < 0 then
        Errs.Add(Format('Freedom case "%s", constraint %d: dof must be one of x,y,z,rx,ry,rz, got "%s"',
          [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].Dof]));
    end;
    SeenConstraintKeys.Free;
    if not hasConstraint then
      Errs.Add(Format('Freedom case "%s" has no constraints -- system would be singular (unconstrained rigid-body motion)',
        [Model.FreedomCases[fc].Id]));
  end;

  // --- load cases ---
  LoadCaseIds := TStringList.Create;
  LoadCaseIds.Sorted := True;
  LoadCaseIds.Duplicates := dupIgnore;
  for lc := 0 to High(Model.LoadCases) do
  begin
    if Model.LoadCases[lc].Id = '' then
      Errs.Add(Format('Load case %d: missing "id"', [lc]));
    if LoadCaseIds.IndexOf(Model.LoadCases[lc].Id) >= 0 then
      Errs.Add(Format('Duplicate load case id "%s"', [Model.LoadCases[lc].Id]))
    else
      LoadCaseIds.Add(Model.LoadCases[lc].Id);

    for i := 0 to High(Model.LoadCases[lc].Loads) do
    begin
      dofOff := DofOffset(Model.LoadCases[lc].Loads[i].Dof);
      CheckFinite(Model.LoadCases[lc].Loads[i].Value,
        Format('Load case "%s", load %d: value', [Model.LoadCases[lc].Id, i]));
      if not NodeIdx.TryGetValue(Model.LoadCases[lc].Loads[i].NodeId, nIdx) then
        Errs.Add(Format('Load case "%s", load %d: references unknown node %d',
          [Model.LoadCases[lc].Id, i, Model.LoadCases[lc].Loads[i].NodeId]))
      else if dofOff >= 0 then
      begin
        if dofOff >= NodeDofCounts[nIdx] then
          Errs.Add(Format('Load case "%s", load %d: dof "%s" is rotational, but node %d has no rotational dof (not connected to any beam element)',
            [Model.LoadCases[lc].Id, i, Model.LoadCases[lc].Loads[i].Dof, Model.LoadCases[lc].Loads[i].NodeId]));
      end;
      if dofOff < 0 then
        Errs.Add(Format('Load case "%s", load %d: dof must be one of x,y,z,rx,ry,rz, got "%s"',
          [Model.LoadCases[lc].Id, i, Model.LoadCases[lc].Loads[i].Dof]));
    end;
  end;

  // --- combinations ---
  for c := 0 to High(Model.Combinations) do
  begin
    comb := Model.Combinations[c];
    if comb.Id = '' then
      Errs.Add(Format('Combination %d: missing "id"', [c]));
    if comb.FreedomCaseId = '' then
    begin
      if Length(Model.FreedomCases) <> 1 then
        Errs.Add(Format('Combination "%s": "freedomCase" is required when the model has more than one freedom case',
          [comb.Id]));
      // else: resolved to the model's sole freedom case by whichever solver runs it
    end
    else if FreedomCaseIds.IndexOf(comb.FreedomCaseId) < 0 then
      Errs.Add(Format('Combination "%s": references unknown freedom case "%s"', [comb.Id, comb.FreedomCaseId]));

    if Length(comb.Terms) = 0 then
      Errs.Add(Format('Combination "%s" has no terms', [comb.Id]));
    for i := 0 to High(comb.Terms) do
      if LoadCaseIds.IndexOf(comb.Terms[i].LoadCaseId) < 0 then
        Errs.Add(Format('Combination "%s": term %d references unknown load case "%s"',
          [comb.Id, i, comb.Terms[i].LoadCaseId]));
  end;

  FreedomCaseIds.Free;
  LoadCaseIds.Free;
  NodeIdx.Free;
  MatIdx.Free;
  PropIdx.Free;
  ElemIdx.Free;

  // --- solver params ---
  // The native parser already rejects a Tolerance that fails to parse as
  // a number at all (see fem_native_model's F2D-style strict parsing);
  // this catches the values that parse fine but aren't physically usable
  // -- 0, negative, NaN, or a magnitude so extreme it can only be a typo.
  if (Model.SolverParams.BeamDivisions < 1) or (Model.SolverParams.BeamDivisions > 200) then
    Errs.Add(Format('SolverParams: BeamDivisions must be between 1 and 200, got %d', [Model.SolverParams.BeamDivisions]));
  if IsNan(Model.SolverParams.Tolerance) or IsInfinite(Model.SolverParams.Tolerance) then
    Errs.Add('SolverParams: Tolerance must be a finite number')
  else if Model.SolverParams.Tolerance <= 0 then
    Errs.Add(Format('SolverParams: Tolerance must be positive, got %g', [Model.SolverParams.Tolerance]))
  else if Model.SolverParams.Tolerance > 1.0 then
    Errs.Add(Format('SolverParams: Tolerance %g is implausibly large (expected roughly 1e-12 to 1e-3) -- likely a typo',
      [Model.SolverParams.Tolerance]))
  else if Model.SolverParams.Tolerance < 1.0E-15 then
    Errs.Add(Format('SolverParams: Tolerance %g is implausibly small (tighter than double-precision can resolve) -- likely a typo',
      [Model.SolverParams.Tolerance]));

  Result := Errs;
end;

end.
