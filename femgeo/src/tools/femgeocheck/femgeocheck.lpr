program femgeocheck;
{$mode objfpc}{$H+}
uses SysUtils, Classes, fem_geometry_types, fem_geometry_io, fem_geometry_validate;
var M:TFEMGeometryModel; D:TDiagnosticArray; E:string; FN:string; I:Integer; S:string;
begin
  if ParamCount>0 then FN:=ParamStr(1) else FN:='-';
  M:=TFEMGeometryModel.Create; try
    if FN='-' then begin if not LoadFGeo(Input,M,E) then begin WriteLn(StdErr,'ERROR GEO000 ',E); Halt(2); end; end
    else if not LoadFGeoFile(FN,M,E) then begin WriteLn(StdErr,'ERROR GEO000 ',E); Halt(2); end;
    if ValidateGeometry(M,D) then begin WriteLn('INFO geometry valid'); Halt(0); end;
    for I:=0 to High(D) do begin case D[I].Severity of gdsWarning:S:='WARNING';gdsError:S:='ERROR';else S:='INFO';end; WriteLn(StdErr,S,' ',D[I].Code,' ',D[I].Message); end;
    Halt(1);
  finally M.Free; end;
end.
