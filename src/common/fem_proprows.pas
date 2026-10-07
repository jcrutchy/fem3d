unit fem_proprows;

// Turns a TSectionProperties record into display rows (group, key, caption,
// value, unit) for GUI property tables. No LCL dependency, so the row list can
// be unit-tested against what femsection writes to a .prop file: every key the
// .prop file contains must have a row here with the same value.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fem_section_types;

type
  TPropDim = (pdNone, pdLength, pdArea, pdLength3, pdLength4, pdAngleDeg);

  TPropRow = record
    Group: string;      // '' for none
    Key: string;        // the .prop key where one exists (e.g. 'Ixx')
    Caption: string;    // human readable
    Dim: TPropDim;
    UnitText: string;   // e.g. 'mm^4'
    Value: Double;
    Pending: Boolean;   // value not computed yet (the torsion constant J)
    InPropFile: Boolean;  // written by femsection to the .prop file
  end;
  TPropRowArray = array of TPropRow;

// JPending = True marks the torsion rows as "still solving" (the quick pass
// has run but the numerical torsion solve has not).
procedure BuildPropRows(const P: TSectionProperties; JPending: Boolean;
  out Rows: TPropRowArray);

function DimUnitText(Dim: TPropDim; const LengthUnit: string): string;

// 6 significant digits, compact: 3230.9, 2.35798E7, 0
function FormatPropValue(V: Double): string;

implementation

function DimUnitText(Dim: TPropDim; const LengthUnit: string): string;
begin
  case Dim of
    pdLength:   Result := LengthUnit;
    pdArea:     Result := LengthUnit + '^2';
    pdLength3:  Result := LengthUnit + '^3';
    pdLength4:  Result := LengthUnit + '^4';
    pdAngleDeg: Result := 'deg';
  else
    Result := '';
  end;
end;

function FormatPropValue(V: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if (V <> V) or (Abs(V) > 1.0E300) then Exit('n/a');
  if Abs(V) < 1.0E-12 then Exit('0');
  Result := Format('%.6g', [V], FS);
end;

procedure BuildPropRows(const P: TSectionProperties; JPending: Boolean;
  out Rows: TPropRowArray);
var
  N: Integer;
  U: string;

  procedure Add(const AGroup, AKey, ACaption: string; ADim: TPropDim;
    AValue: Double; AInFile: Boolean; APending: Boolean = False);
  begin
    SetLength(Rows, N + 1);
    Rows[N].Group := AGroup;
    Rows[N].Key := AKey;
    Rows[N].Caption := ACaption;
    Rows[N].Dim := ADim;
    Rows[N].UnitText := DimUnitText(ADim, U);
    Rows[N].Value := AValue;
    Rows[N].Pending := APending;
    Rows[N].InPropFile := AInFile;
    Inc(N);
  end;

begin
  N := 0;
  Rows := nil;
  U := P.LengthUnit;
  if U = '' then U := 'mm';

  Add('Geometry', 'Area', 'Area A', pdArea, P.Area, True);
  Add('Geometry', 'Perimeter', 'Perimeter', pdLength, P.Perimeter, True);
  Add('Geometry', 'CentroidX', 'Centroid x', pdLength, P.CentroidX, True);
  Add('Geometry', 'CentroidY', 'Centroid y', pdLength, P.CentroidY, True);
  Add('Geometry', 'BBoxXMin', 'Bounding box x min', pdLength, P.BBoxXMin, True);
  Add('Geometry', 'BBoxXMax', 'Bounding box x max', pdLength, P.BBoxXMax, True);
  Add('Geometry', 'BBoxYMin', 'Bounding box y min', pdLength, P.BBoxYMin, True);
  Add('Geometry', 'BBoxYMax', 'Bounding box y max', pdLength, P.BBoxYMax, True);
  Add('Geometry', 'CxPos', 'Extreme fibre +x (from centroid)', pdLength, P.CxPos, True);
  Add('Geometry', 'CxNeg', 'Extreme fibre -x (from centroid)', pdLength, P.CxNeg, True);
  Add('Geometry', 'CyPos', 'Extreme fibre +y (from centroid)', pdLength, P.CyPos, True);
  Add('Geometry', 'CyNeg', 'Extreme fibre -y (from centroid)', pdLength, P.CyNeg, True);

  Add('Second moments of area', 'Ixx', 'Ixx', pdLength4, P.Ixx, True);
  Add('Second moments of area', 'Iyy', 'Iyy', pdLength4, P.Iyy, True);
  Add('Second moments of area', 'Ixy', 'Ixy (product)', pdLength4, P.Ixy, True);
  Add('Second moments of area', 'I1', 'I1 (principal, major)', pdLength4, P.I1, True);
  Add('Second moments of area', 'I2', 'I2 (principal, minor)', pdLength4, P.I2, True);
  Add('Second moments of area', 'ThetaPrincipalDeg', 'Principal axis angle', pdAngleDeg, P.ThetaPrincipalDeg, True);

  Add('Radii of gyration', 'rx', 'rx', pdLength, P.rx, True);
  Add('Radii of gyration', 'ry', 'ry', pdLength, P.ry, True);
  Add('Radii of gyration', 'r1', 'r1 (principal)', pdLength, P.r1, True);
  Add('Radii of gyration', 'r2', 'r2 (principal)', pdLength, P.r2, True);

  Add('Section moduli', 'ZxPos', 'Zx+ (elastic)', pdLength3, P.ZxPos, True);
  Add('Section moduli', 'ZxNeg', 'Zx- (elastic)', pdLength3, P.ZxNeg, True);
  Add('Section moduli', 'Zx', 'Zx (min elastic)', pdLength3, P.Zx, True);
  Add('Section moduli', 'ZyPos', 'Zy+ (elastic)', pdLength3, P.ZyPos, True);
  Add('Section moduli', 'ZyNeg', 'Zy- (elastic)', pdLength3, P.ZyNeg, True);
  Add('Section moduli', 'Zy', 'Zy (min elastic)', pdLength3, P.Zy, True);
  Add('Section moduli', 'Sx', 'Sx (plastic)', pdLength3, P.Sx, True);
  Add('Section moduli', 'Sy', 'Sy (plastic)', pdLength3, P.Sy, True);

  Add('Torsion', 'J', 'J (St. Venant)', pdLength4, P.J, True, JPending);
  Add('Torsion', 'Ip', 'Ip (polar, Ixx + Iyy)', pdLength4, P.Ip, True);
  Add('Torsion', 'JThinWalled', 'J thin-walled open estimate', pdLength4, P.JThinWalled, False);

  Add('Beam property (for .fem)', 'BeamIy', 'Iy (about principal axis)', pdLength4, P.BeamIy, False);
  Add('Beam property (for .fem)', 'BeamIz', 'Iz (about principal axis)', pdLength4, P.BeamIz, False);
  Add('Beam property (for .fem)', 'BeamCy', 'Cy (extreme fibre, local y)', pdLength, P.BeamCy, False);
  Add('Beam property (for .fem)', 'BeamCz', 'Cz (extreme fibre, local z)', pdLength, P.BeamCz, False);
  Add('Beam property (for .fem)', 'BeamRt', 'Rt (max distance from centroid)', pdLength, P.BeamRt, False);
  Add('Beam property (for .fem)', 'BeamThetaDeg', 'Local axes rotation', pdAngleDeg, P.BeamThetaDeg, False);
end;

end.
