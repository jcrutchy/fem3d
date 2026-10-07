program femsecedit;

// Native FEM3D section editor / analyser.
//
//   femsecedit [section.fgeo] [--screenshot out.png] [--size WxH]
//
// Opens a FEM3DGEO section, draws it and shows every section property live,
// computed by the same units as the femsection command-line tool.

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  secedit_main, secedit_view;

begin
  Application.Title := 'FEM3D Section Editor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TSecEditForm, SecEditForm);
  Application.Run;
end.
