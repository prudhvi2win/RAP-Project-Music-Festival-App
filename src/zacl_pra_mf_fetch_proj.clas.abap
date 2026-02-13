CLASS zcl_pra_mf_fetch_proj DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider .

    TYPES: BEGIN OF ty_project_custom_entity,
             ProjectID   TYPE c LENGTH 24,
             ProjectName TYPE c LENGTH 40,
             StartDate   TYPE c LENGTH 8,
             EndDate     TYPE c LENGTH 8,
             CostCenter  TYPE c LENGTH 10,
             Status      TYPE c LENGTH 10,
             Nav         TYPE c LENGTH 120,
           END OF ty_project_custom_entity.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_PRA_MF_FETCH_PROJ IMPLEMENTATION.


  METHOD if_rap_query_provider~select.

    " check if any project is passed as filter; if not exit early and avoid remote call
    DATA projects TYPE STANDARD TABLE OF ty_project_custom_entity.
    TRY.
        DATA(filter) = io_request->get_filter( )->get_as_ranges( ).
        DATA(project_range) = filter[ 1 ]-range.
        DATA(project_id) = project_range[ 1 ]-low.

      CATCH cx_rap_query_filter_no_range cx_sy_itab_line_not_found ##NO_HANDLER.
        " if exception is raised, behave same as if filter not passed -> return 0 rows
    ENDTRY.
    IF project_id IS INITIAL.
      io_response->set_data( it_data = projects ).
      io_response->set_total_number_of_records( 0 ).
      RETURN.
    ENDIF.

    " get details of project from s4 by using remote proxy of service consumption model
    TRY.
        DATA(http_client) = cl_web_http_client_manager=>create_by_http_destination(
                              cl_http_destination_provider=>create_by_comm_arrangement(
                                comm_scenario  = 'ZPRA_MF_CS_ENT_PROJ'
                                service_id     = 'ZPRA_MF_OUT_ENT_PROJ_REST' ) ).

        DATA(remote_proxy) = /iwbep/cl_cp_factory_remote=>create_v2_remote_proxy(
                                is_proxy_model_key       = VALUE #( repository_id       = 'DEFAULT'
                                                                    proxy_model_id      = 'ZCL_PRA_MF_SCM_ENT_PROJ'
                                                                    proxy_model_version = '001' )
                                io_http_client             = http_client
                                iv_relative_service_root   = '/sap/opu/odata/sap/API_ENTERPRISE_PROJECT_SRV;v=0002/'  " = the service endpoint in the service binding in PRV' ).
                              ).
        DATA(project_request) = remote_proxy->create_resource_for_entity_set( 'A_ENTERPRISE_PROJECT' )->create_request_for_read( ).

        project_request->set_filter( project_request->create_filter_factory( )->create_by_range(
                                      iv_property_path = 'PROJECT'
                                      it_range         = project_range ) ).

        project_request->execute( ).

        DATA(project_response) = project_request->get_response( ).

        DATA s4_projects  TYPE TABLE OF zcl_pra_mf_scm_ent_proj=>tys_a_enterprise_project_type.
        project_response->get_business_data( IMPORTING et_business_data = s4_projects ).

        " get host of remote system to be able to form url for navigation on click
        DATA(s4_host) = http_client->get_http_request( )->get_header_field( if_web_http_header=>host ).

        projects = VALUE #( BASE projects FOR s4_project IN s4_projects (
                                  projectid = s4_project-project
                                  projectname = s4_project-project_description
                                  startdate = s4_project-project_start_date
                                  enddate = s4_project-project_end_date
                                  costcenter = s4_project-responsible_cost_center
                                  status = COND #( WHEN s4_project-processing_status EQ '00' THEN 'Created' ) ##NO_TEXT
                                  Nav = |https://{ s4_host }/ui#EnterpriseProject-planProject?EnterpriseProject={ s4_project-project }|
                          )  ) .

        io_response->set_data( projects ).
        io_response->set_total_number_of_records( lines( projects ) ).

      CATCH cx_http_dest_provider_error
            cx_web_http_client_error
            /iwbep/cx_gateway INTO DATA(lx_prov_error).
        MESSAGE e009(zpra_mf_msg_cls) INTO DATA(lv_msg).
    ENDTRY.

  ENDMETHOD.
ENDCLASS.
