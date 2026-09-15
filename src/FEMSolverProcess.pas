unit FEMSolverProcess;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Process;

type
  TSolverProcessResult = record
    Started:Boolean;
    ExitCode:Integer;
    OutputText:string;
    ErrorText:string;
  end;

  TSolverProcessRunner = class
  public
    class function Run(const Executable:string; const Parameters:array of string; out R:TSolverProcessResult):Boolean;
  end;

implementation

class function TSolverProcessRunner.Run(const Executable:string; const Parameters:array of string; out R:TSolverProcessResult):Boolean;
var P:TProcess; I,N:Integer; S:string;
begin
  FillChar(R,SizeOf(R),0); R.ExitCode:=-1; Result:=False;
  if not FileExists(Executable) then begin R.ErrorText:='Solver executable not found: '+Executable; Exit; end;
  P:=TProcess.Create(nil); try
    P.Executable:=Executable;
    for I:=Low(Parameters) to High(Parameters) do P.Parameters.Add(Parameters[I]);
    P.Options:=[poWaitOnExit,poUsePipes]; P.Execute; R.Started:=True; R.ExitCode:=P.ExitStatus;
    N:=P.Output.NumBytesAvailable; if N>0 then begin SetLength(S,N); P.Output.ReadBuffer(S[1],N); R.OutputText:=S; end;
    N:=P.Stderr.NumBytesAvailable; if N>0 then begin SetLength(S,N); P.Stderr.ReadBuffer(S[1],N); R.ErrorText:=S; end;
    Result:=True;
  finally P.Free end;
end;

end.

