unit secedit_trace;

// Opt-in diagnostic output: set the environment variable FEMSECEDIT_TRACE to see
// what the window is doing on stderr. Costs nothing when it is not set.

{$mode objfpc}{$H+}

interface

procedure Trace(const S: string);

implementation

uses
  SysUtils;

var
  Enabled: Boolean = False;
  Checked: Boolean = False;

procedure Trace(const S: string);
begin
  if not Checked then
  begin
    Enabled := GetEnvironmentVariable('FEMSECEDIT_TRACE') <> '';
    Checked := True;
  end;
  if not Enabled then Exit;
  try
    WriteLn(StdErr, 'trace: ', S);
    Flush(StdErr);
  except
  end;
end;

end.
