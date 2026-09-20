unit FEMResultFields;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMTypes, FEMModel, FEMResults, FEMElements;

type
  TResultLocation = (rlNode, rlElement);

  TResultField = class
  public
    ID: string;
    Name: string;
    Units: string;
    Location: TResultLocation;
    EntityIDs: array of Integer;
    Values: array of Double;
    constructor Create(const AID,AName,AUnits:string; ALocation:TResultLocation);
    function Count:Integer;
    function ValueForEntity(EntityID:Integer):Double;
    function MinValue:Double;
    function MaxValue:Double;
    function AbsMaxValue:Double;
  end;

  TResultFieldCollection = class
  private
    FItems: array of TResultField;
  public
    destructor Destroy; override;
    procedure Clear;
    procedure Add(F:TResultField);
    function Count:Integer;
    function Item(I:Integer):TResultField;
    function Find(const ID:string):TResultField;
  end;

  TResultExpressionEvaluator = class
  private
    FText: string;
    FPos: Integer;
    FField: TResultFieldCollection;
    FLocation: TResultLocation;
    FEntityID: Integer;
    function Peek:Char;
    procedure SkipSpaces;
    function Match(C:Char):Boolean;
    function ParseExpression(out V:Double):Boolean;
    function ParseComparison(out V:Double):Boolean;
    function ParseTerm(out V:Double):Boolean;
    function ParseFactor(out V:Double):Boolean;
    function ParsePrimary(out V:Double):Boolean;
    function ParseIdentifier(out S:string):Boolean;
    function ParseNumber(out V:Double):Boolean;
  public
    constructor Create(AFields:TResultFieldCollection);
    function Evaluate(const Expression:string; Location:TResultLocation; EntityID:Integer; out V:Double; out ErrorText:string):Boolean;
  end;

function BuildResultFields(const M:TFEMModel; const R:TFEMResultDocument):TResultFieldCollection;

implementation

constructor TResultField.Create(const AID,AName,AUnits:string; ALocation:TResultLocation);
begin inherited Create; ID:=AID; Name:=AName; Units:=AUnits; Location:=ALocation; end;
function TResultField.Count:Integer; begin Result:=Length(Values); end;
function TResultField.ValueForEntity(EntityID:Integer):Double;
var I:Integer;
begin Result:=0; for I:=0 to High(EntityIDs) do if EntityIDs[I]=EntityID then Exit(Values[I]); end;
function TResultField.MinValue:Double;
var I:Integer;
begin if Length(Values)=0 then Exit(0); Result:=Values[0]; for I:=1 to High(Values) do Result:=Min(Result,Values[I]); end;
function TResultField.MaxValue:Double;
var I:Integer;
begin if Length(Values)=0 then Exit(0); Result:=Values[0]; for I:=1 to High(Values) do Result:=Max(Result,Values[I]); end;
function TResultField.AbsMaxValue:Double;
var I:Integer;
begin Result:=0; for I:=0 to High(Values) do Result:=Max(Result,Abs(Values[I])); end;

destructor TResultFieldCollection.Destroy; begin Clear; inherited Destroy; end;
procedure TResultFieldCollection.Clear; var I:Integer; begin for I:=0 to High(FItems) do FItems[I].Free; SetLength(FItems,0); end;
procedure TResultFieldCollection.Add(F:TResultField); begin SetLength(FItems,Length(FItems)+1);FItems[High(FItems)]:=F; end;
function TResultFieldCollection.Count:Integer; begin Result:=Length(FItems); end;
function TResultFieldCollection.Item(I:Integer):TResultField; begin Result:=FItems[I]; end;
function TResultFieldCollection.Find(const ID:string):TResultField; var I:Integer; begin Result:=nil; for I:=0 to High(FItems) do if SameText(FItems[I].ID,ID) then Exit(FItems[I]); end;

function BuildResultFields(const M:TFEMModel; const R:TFEMResultDocument):TResultFieldCollection;
var F:TResultField; I,J,N,SI:Integer; Mag:Double; Elt:TBeam3D; C:TElementContext; EF:TBeamEndForces; S,Axial:Double;
begin
  Result:=TResultFieldCollection.Create;
  // Node IDs are not necessarily contiguous, so use the model's DOF numbering for result mapping.
  C.Model:=M; C.Numbering:=M.CreateDOFNumbering;
  try
    for J:=0 to 5 do begin
      F:=TResultField.Create('U'+IntToStr(J),'Displacement '+IntToStr(J+1),'m',rlNode);
      SetLength(F.EntityIDs,Length(M.Nodes)); SetLength(F.Values,Length(M.Nodes));
      for I:=0 to High(M.Nodes) do begin F.EntityIDs[I]:=M.Nodes[I].ID; N:=C.Numbering.DOF(M.Nodes[I].ID,J); if (N>=0) and (N<Length(R.Displacements)) then F.Values[I]:=R.Displacements[N]; end;
      Result.Add(F);
    end;
    F:=TResultField.Create('UMAG','Displacement magnitude','m',rlNode); SetLength(F.EntityIDs,Length(M.Nodes));SetLength(F.Values,Length(M.Nodes));
    for I:=0 to High(M.Nodes) do begin F.EntityIDs[I]:=M.Nodes[I].ID; Mag:=0; for J:=0 to 2 do begin N:=C.Numbering.DOF(M.Nodes[I].ID,J); if (N>=0) and (N<Length(R.Displacements)) then Mag:=Mag+Sqr(R.Displacements[N]); end; F.Values[I]:=Sqrt(Mag); end; Result.Add(F);
    for J:=0 to 5 do begin
      F:=TResultField.Create('R'+IntToStr(J),'Reaction '+IntToStr(J+1),'N',rlNode); SetLength(F.EntityIDs,Length(M.Nodes));SetLength(F.Values,Length(M.Nodes));
      for I:=0 to High(M.Nodes) do begin F.EntityIDs[I]:=M.Nodes[I].ID; N:=C.Numbering.DOF(M.Nodes[I].ID,J); if (N>=0) and (N<Length(R.Reactions)) then F.Values[I]:=R.Reactions[N]; end; Result.Add(F);
    end;
    F:=TResultField.Create('RMAG','Reaction magnitude','N',rlNode); SetLength(F.EntityIDs,Length(M.Nodes));SetLength(F.Values,Length(M.Nodes));
    for I:=0 to High(M.Nodes) do begin F.EntityIDs[I]:=M.Nodes[I].ID; Mag:=0; for J:=0 to 2 do begin N:=C.Numbering.DOF(M.Nodes[I].ID,J); if (N>=0) and (N<Length(R.Reactions)) then Mag:=Mag+Sqr(R.Reactions[N]); end; F.Values[I]:=Sqrt(Mag); end; Result.Add(F);

    F:=TResultField.Create('AXIAL_STRESS','Beam axial stress','Pa',rlElement); SetLength(F.EntityIDs,Length(M.Elements));SetLength(F.Values,Length(M.Elements));
    Elt:=TBeam3D.Create; try
      for I:=0 to High(M.Elements) do begin F.EntityIDs[I]:=M.Elements[I].ID; F.Values[I]:=0; if not SameText(M.Elements[I].Kind,'BEAM3D') then Continue; if Elt.RecoverEndForces(C,M.Elements[I],R.Displacements,EF) then begin Axial:=(EF.Node1[0]-EF.Node2[0])*0.5; SI:=M.FindSection(M.Elements[I].SectionID); if SI>=0 then begin S:=M.Sections[SI].Area; if Abs(S)>1e-20 then F.Values[I]:=Axial/S; end; end; end;
    finally Elt.Free end; Result.Add(F);
    // Beam end-force result fields. Values are signed and reported at the
    // requested end, using the beam's local force convention from recovery.
    // These are element fields so they can be contoured and used in expressions.
    Elt:=TBeam3D.Create; try
      for J:=0 to 11 do begin
        case J of
          0: begin F:=TResultField.Create('N1','Beam axial force - end 1','N',rlElement); end;
          1: begin F:=TResultField.Create('VY1','Beam local shear Y - end 1','N',rlElement); end;
          2: begin F:=TResultField.Create('VZ1','Beam local shear Z - end 1','N',rlElement); end;
          3: begin F:=TResultField.Create('T1','Beam torsion - end 1','Nm',rlElement); end;
          4: begin F:=TResultField.Create('MY1','Beam bending moment Y - end 1','Nm',rlElement); end;
          5: begin F:=TResultField.Create('MZ1','Beam bending moment Z - end 1','Nm',rlElement); end;
          6: begin F:=TResultField.Create('N2','Beam axial force - end 2','N',rlElement); end;
          7: begin F:=TResultField.Create('VY2','Beam local shear Y - end 2','N',rlElement); end;
          8: begin F:=TResultField.Create('VZ2','Beam local shear Z - end 2','N',rlElement); end;
          9: begin F:=TResultField.Create('T2','Beam torsion - end 2','Nm',rlElement); end;
          10: begin F:=TResultField.Create('MY2','Beam bending moment Y - end 2','Nm',rlElement); end;
          11: begin F:=TResultField.Create('MZ2','Beam bending moment Z - end 2','Nm',rlElement); end;
        end;
        SetLength(F.EntityIDs,Length(M.Elements)); SetLength(F.Values,Length(M.Elements));
        for I:=0 to High(M.Elements) do begin
          F.EntityIDs[I]:=M.Elements[I].ID; F.Values[I]:=0;
          if SameText(M.Elements[I].Kind,'BEAM3D') and Elt.RecoverEndForces(C,M.Elements[I],R.Displacements,EF) then begin
            if J<6 then F.Values[I]:=EF.Node1[J] else F.Values[I]:=EF.Node2[J-6];
          end;
        end;
        Result.Add(F);
      end;
    finally Elt.Free end;
  finally C.Numbering.Free end;
end;

constructor TResultExpressionEvaluator.Create(AFields:TResultFieldCollection); begin inherited Create; FField:=AFields; end;
function TResultExpressionEvaluator.Peek:Char; begin if FPos>Length(FText) then Result:=#0 else Result:=FText[FPos]; end;
procedure TResultExpressionEvaluator.SkipSpaces; begin while (FPos<=Length(FText)) and (FText[FPos]<=' ') do Inc(FPos); end;
function TResultExpressionEvaluator.Match(C:Char):Boolean; begin SkipSpaces; Result:=Peek=C; if Result then Inc(FPos); end;
function TResultExpressionEvaluator.ParseNumber(out V:Double):Boolean; var S:string; Start:Integer;
begin SkipSpaces; Start:=FPos; while Peek in ['0'..'9','.','e','E','+','-'] do begin if ((Peek='+') or (Peek='-')) and (FPos>Start) and not (FText[FPos-1] in ['e','E']) then Break; Inc(FPos); end; S:=Copy(FText,Start,FPos-Start); Result:=(S<>'') and TryStrToFloat(S,V); end;
function TResultExpressionEvaluator.ParseIdentifier(out S:string):Boolean; var Start:Integer;
begin SkipSpaces; Start:=FPos; if not (Peek in ['A'..'Z','a'..'z','_']) then begin S:='';Exit(False);end; Inc(FPos); while Peek in ['A'..'Z','a'..'z','0'..'9','_'] do Inc(FPos); S:=Copy(FText,Start,FPos-Start);Result:=True;end;
function TResultExpressionEvaluator.ParsePrimary(out V:Double):Boolean;
var S:string; A,B,C:Double; F:TResultField;
begin
  SkipSpaces;
  if Match('(') then begin Result:=ParseExpression(V) and Match(')');Exit;end;
  if ParseNumber(V) then Exit(True);
  if not ParseIdentifier(S) then Exit(False);
  if Match('(') then begin
    if SameText(S,'IF') then begin
      if not ParseExpression(A) then Exit(False);
      if not Match(',') then Exit(False);
      if not ParseExpression(B) then Exit(False);
      if not Match(',') then Exit(False);
      if not ParseExpression(C) then Exit(False);
      if A<>0 then V:=B else V:=C;
    end else begin
      if not ParseExpression(A) then Exit(False);
      if SameText(S,'SQRT') then V:=Sqrt(Max(0,A))
      else if SameText(S,'ABS') then V:=Abs(A)
      else if SameText(S,'EXP') then V:=Exp(A)
      else if SameText(S,'LOG10') then begin if A<=0 then Exit(False); V:=Log10(A); end
      else begin
        if not Match(',') then Exit(False);
        if not ParseExpression(B) then Exit(False);
        if SameText(S,'MIN') then V:=Min(A,B)
        else if SameText(S,'MAX') then V:=Max(A,B)
        else if SameText(S,'POW') then V:=Power(A,B)
        else if SameText(S,'CLAMP') then begin
          if not Match(',') then Exit(False);
          if not ParseExpression(C) then Exit(False);
          V:=Max(B,Min(C,A));
        end
        else Exit(False);
      end;
    end;
    Result:=Match(')'); Exit;
  end;
  F:=FField.Find(S);
  if F=nil then begin if SameText(S,'PI') then V:=Pi else Exit(False); end
  else begin if F.Location<>FLocation then Exit(False); V:=F.ValueForEntity(FEntityID); end;
  Result:=True;
end;
function TResultExpressionEvaluator.ParseFactor(out V:Double):Boolean;
begin SkipSpaces; if Match('+') then Result:=ParseFactor(V) else if Match('-') then begin Result:=ParseFactor(V);V:=-V;end else Result:=ParsePrimary(V); end;
function TResultExpressionEvaluator.ParseTerm(out V:Double):Boolean;
var B:Double; Op:Char;
begin Result:=ParseFactor(V); while Result do begin SkipSpaces; Op:=Peek; if not (Op in ['*','/']) then Break; Inc(FPos); if not ParseFactor(B) then Exit(False); if Op='*' then V:=V*B else if Abs(B)<1e-300 then Exit(False) else V:=V/B; end; end;
function TResultExpressionEvaluator.ParseComparison(out V:Double):Boolean;
var B:Double; Op1,Op2:Char;
begin
  Result:=ParseTerm(V); if not Result then Exit;
  SkipSpaces;
  Op1:=Peek;
  if (Op1='=') or (Op1='<') or (Op1='>') or (Op1='!') then begin
    Inc(FPos); Op2:=Peek;
    if (Op1='<') and (Op2='=') then Inc(FPos)
    else if (Op1='>') and (Op2='=') then Inc(FPos)
    else if (Op1='=') and (Op2='=') then Inc(FPos)
    else if (Op1='!') and (Op2='=') then Inc(FPos)
    else if Op1='=' then begin end
    else if (Op1='<') or (Op1='>') then begin end
    else Exit(False);
    if not ParseTerm(B) then Exit(False);
    if (Op1='=') then V:=Ord(V=B)
    else if (Op1='!') then V:=Ord(V<>B)
    else if (Op1='<') then begin if Op2='=' then V:=Ord(V<=B) else V:=Ord(V<B); end
    else if (Op1='>') then begin if Op2='=' then V:=Ord(V>=B) else V:=Ord(V>B); end;
  end;
end;

function TResultExpressionEvaluator.ParseExpression(out V:Double):Boolean;
var B:Double; Op:Char;
begin
  Result:=ParseComparison(V); while Result do begin SkipSpaces; Op:=Peek; if not (Op in ['+','-']) then Break; Inc(FPos); if not ParseComparison(B) then Exit(False); if Op='+' then V:=V+B else V:=V-B; end;
end;
function TResultExpressionEvaluator.Evaluate(const Expression:string; Location:TResultLocation; EntityID:Integer; out V:Double; out ErrorText:string):Boolean;
begin FText:=Expression;FPos:=1;FLocation:=Location;FEntityID:=EntityID;ErrorText:='';Result:=ParseExpression(V);SkipSpaces;if Result and (FPos<=Length(FText)) then Result:=False;if not Result then ErrorText:=Format('Invalid result expression near character %d.',[FPos]); end;

end.
