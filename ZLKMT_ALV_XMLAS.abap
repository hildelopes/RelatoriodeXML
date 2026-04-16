*&---------------------------------------------------------------------*
*& Report ZLKMT_ALV_XMLAS
*& ALV Report for /LKMT/COM_XMLAS - XMLs Auxiliares
*& Double-click a row to display the XML content.
*&---------------------------------------------------------------------*
REPORT zlkmt_alv_xmlas.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_output,
    mandt TYPE mandt,
    aplic TYPE /lkmt/com_xmlas-aplic,
    obkey TYPE /lkmt/com_xmlas-obkey,
    tpeve TYPE /lkmt/com_xmlas-tpeve,
    dheve TYPE /lkmt/com_xmlas-dheve,
    idxml TYPE /lkmt/com_xmlas-idxml,
    crusr TYPE /lkmt/com_xmlas-crusr,
    crdat TYPE /lkmt/com_xmlas-crdat,
    crtim TYPE /lkmt/com_xmlas-crtim,
    xmls  TYPE xstring,
  END OF ty_output.

TYPES: tt_output TYPE STANDARD TABLE OF ty_output WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Forward declaration — must appear before DATA referencing lcl_events
*----------------------------------------------------------------------*
CLASS lcl_events DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* Global data
*----------------------------------------------------------------------*
DATA:
  gt_output  TYPE tt_output,
  go_salv    TYPE REF TO cl_salv_table,
  go_events  TYPE REF TO lcl_events.

" Auxiliary variables used only to define SELECT-OPTIONS types.
" SELECT-OPTIONS FOR table-field implicitly tries to build a flat work area
" for the whole table; /LKMT/COM_XMLAS has RAWSTRING so that fails.
" Referencing individual-typed DATA variables avoids this restriction.
DATA: gv_aplic TYPE /lkmt/com_xmlas-aplic.
DATA: gv_obkey TYPE /lkmt/com_xmlas-obkey.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-t01.
  SELECT-OPTIONS:
    so_aplic FOR gv_aplic,
    so_obkey FOR gv_obkey.
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* Start of selection
*----------------------------------------------------------------------*
START-OF-SELECTION.

  SELECT mandt
         aplic
         obkey
         tpeve
         dheve
         idxml
         crusr
         crdat
         crtim
         xmls
    FROM /lkmt/com_xmlas
    INTO TABLE gt_output
   WHERE aplic IN so_aplic
     AND obkey IN so_obkey.

  IF sy-subrc <> 0.
    MESSAGE 'Nenhum registro encontrado para os filtros informados.'
            TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  PERFORM display_alv.

*----------------------------------------------------------------------*
* FORM display_alv
*----------------------------------------------------------------------*
FORM display_alv.

  DATA: lo_columns     TYPE REF TO cl_salv_columns_table,
        lo_functions   TYPE REF TO cl_salv_functions_list,
        lo_display     TYPE REF TO cl_salv_display_settings,
        lo_events_salv TYPE REF TO cl_salv_events_table.

  TRY.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = go_salv
      CHANGING
        t_table      = gt_output ).
  CATCH cx_salv_msg INTO DATA(lx_msg).
    MESSAGE lx_msg->get_text( ) TYPE 'E'.
    RETURN.
  ENDTRY.

  lo_functions = go_salv->get_functions( ).
  lo_functions->set_all( abap_true ).

  lo_display = go_salv->get_display_settings( ).
  lo_display->set_striped_pattern( cl_salv_display_settings=>true ).
  lo_display->set_list_header( 'Relatório de XML - /LKMT/COM_XMLAS' ).

  lo_columns = go_salv->get_columns( ).
  lo_columns->set_optimize( abap_true ).

  " Hide system/binary columns
  TRY.
    lo_columns->get_column( 'MANDT' )->set_visible( abap_false ).
  CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
    lo_columns->get_column( 'XMLS' )->set_visible( abap_false ).
  CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  PERFORM set_column_labels USING lo_columns.

  CREATE OBJECT go_events.
  lo_events_salv = go_salv->get_event( ).
  SET HANDLER go_events->on_double_click FOR lo_events_salv.

  go_salv->display( ).

ENDFORM.

*----------------------------------------------------------------------*
* FORM set_column_labels
*----------------------------------------------------------------------*
FORM set_column_labels USING io_columns TYPE REF TO cl_salv_columns_table.

  DATA lo_col TYPE REF TO cl_salv_column_table.

  DEFINE set_col_label.
    TRY.
      lo_col ?= io_columns->get_column( &1 ).
      lo_col->set_short_text( &2 ).
      lo_col->set_medium_text( &3 ).
      lo_col->set_long_text( &4 ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.
  END-OF-DEFINITION.

  set_col_label 'APLIC'  'Aplic.'   'Aplicação'    'Código da Aplicação'.
  set_col_label 'OBKEY'  'Chave'    'Chave Obj.'   'Chave do Objeto'.
  set_col_label 'TPEVE'  'Tp.Eve.'  'Tipo Evento'  'Tipo de Evento SEFAZ'.
  set_col_label 'DHEVE'  'Dt/Hr'    'Data/Hr Eve.' 'Data e Hora do Evento'.
  set_col_label 'IDXML'  'ID XML'   'Ident. XML'   'Identificador XML'.
  set_col_label 'CRUSR'  'Usuário'  'Usuário Cr.'  'Usuário Criador'.
  set_col_label 'CRDAT'  'Dt Cria.' 'Data Criação' 'Data de Criação'.
  set_col_label 'CRTIM'  'Hr Cria.' 'Hora Criação' 'Hora de Criação'.

ENDFORM.

*----------------------------------------------------------------------*
* Local class: ALV event handler
*----------------------------------------------------------------------*
CLASS lcl_events DEFINITION.
  PUBLIC SECTION.
    METHODS:
      on_double_click
        FOR EVENT double_click
        OF cl_salv_events_table
        IMPORTING row col.
ENDCLASS.

CLASS lcl_events IMPLEMENTATION.

  METHOD on_double_click.

    DATA: lv_xml      TYPE string,
          lv_subrc    TYPE sysubrc,
          lcl_xml_doc TYPE REF TO cl_xml_document.

    IF row = 0 OR row > lines( gt_output ).
      RETURN.
    ENDIF.

    DATA(ls_row) = gt_output[ row ].

    IF ls_row-xmls IS INITIAL.
      MESSAGE 'Nenhum conteúdo XML encontrado para este registro.'
              TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    " Convert XSTRING → STRING before parsing
    " XML files are typically encoded in UTF-8; adjust codepage if needed.
    TRY.
      lv_xml = cl_abap_codepage=>convert_from(
                 source   = ls_row-xmls
                 codepage = 'UTF-8' ).
    CATCH cx_sy_codepage_converter_init
          cx_sy_conversion_codepage INTO DATA(lx_cp).
      MESSAGE |Erro ao converter o conteúdo XML: { lx_cp->get_text( ) }|
              TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDTRY.

    CREATE OBJECT lcl_xml_doc.
    lv_subrc = lcl_xml_doc->parse_string( stream = lv_xml ).
    IF lv_subrc IS INITIAL.
      lcl_xml_doc->display( ).
    ELSE.
      MESSAGE |Erro ao interpretar o XML (RC={ lv_subrc }). Verifique o conteúdo.|
              TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
