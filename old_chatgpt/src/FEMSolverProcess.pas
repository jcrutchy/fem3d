unit FEMSolverProcess;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Process;

const
  SOLVER_PROCESS_TIMEOUT_MS = 600000;

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
    P.Options:=[poUsePipes];
    try
      P.Execute;
      R.Started:=True;
      if not P.WaitOnExit(SOLVER_PROCESS_TIMEOUT_MS) then
      begin
        R.ErrorText:='Solver process timed out after '+IntToStr(SOLVER_PROCESS_TIMEOUT_MS div 1000)+' seconds.';
        try P.Terminate(1); except end;
        try P.WaitOnExit; except end;
        R.ExitCode:=-2;
        Exit;
      end;
      R.ExitCode:=P.ExitStatus;
      N:=P.Output.NumBytesAvailable; if N>0 then begin SetLength(S,N); P.Output.ReadBuffer(S[1],N); R.OutputText:=S; end;
      N:=P.Stderr.NumBytesAvailable; if N>0 then begin SetLength(S,N); P.Stderr.ReadBuffer(S[1],N); R.ErrorText:=S; end;
      Result:=True;
    except
      on E:Exception do R.ErrorText:='Unable to execute solver: '+E.Message;
    end;
  finally P.Free end;
end;

end.
