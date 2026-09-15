program fem3d;
{$mode objfpc}{$H+}
{$apptype GUI}
uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}cthreads,{$ENDIF}{$ENDIF}
  Interfaces, Forms, lazopenglcontext, MainUnit;
begin
  RequireDerivedFormResource := False;
  Application.Title:='FEM3D';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.

