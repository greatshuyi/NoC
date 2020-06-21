// $Id: vcr_sw_alloc_sep_if.v 5188 2012-08-30 00:31:31Z dub $

/*
 Copyright (c) 2007-2012, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//==============================================================================
// switch allocator variant usign separable input-first allocation
//==============================================================================


import topo_pkg::*;


module sw_alloc_sep_if (
    clk, 
    rst_n, 
    active_ip, 
    active_op, 
    route_ip_ivc_op, 
    req_nonspec_ip_ivc, 
    req_spec_ip_ivc, 
    gnt_ip, 
    sel_ip_ivc, 
    gnt_op, 
    sel_op_ip, 
    sel_op_ivc
);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"

//==============================================================================
// Parameters
//==============================================================================
   
// number of VCs per Port
parameter P_NUM_VCS   = 4;

// number of input and output ports on switch
parameter P_NUM_PORTS = 5;

// arbiter type used in sw allocator
parameter P_SW_ARB    = `ARBITER_TYPE_ROUND_ROBIN_BINARY;

// speculation type used by router
parameter P_SW_SPEC   = `SW_ALLOC_SPEC_TYPE_REQ;

// total number of VCS
localparam NUM_VCS    = P_NUM_VCS * P_NUM_PORTS;


//==============================================================================
// Interfaces
//==============================================================================

input                                  clk;
input                                  rst_n;

// clock enable signals
input [P_NUM_PORTS-1:0]                active_ip;
input [P_NUM_PORTS-1:0]                active_op;

// destination port selects
input [NUM_VCS-1:0]                    route_ip_ivc_op;

// non-speculative switch requests
input [P_NUM_PORTS*P_NUM_VCS-1:0]      req_nonspec_ip_ivc;

// speculative switch requests
input [P_NUM_PORTS*P_NUM_VCS-1:0]      req_spec_ip_ivc;

// grants
output wire [P_NUM_PORTS-1:0]          gnt_ip;

// indicate which VC at a given port is granted
output wire [NUM_VCS-1:0]              sel_ip_ivc;

// grants for output ports
output wire [P_NUM_PORTS-1:0]          gnt_op;

// selected input ports (if any)
output wire [NUM_VCS-1:0]              sel_op_ip;

// selected input VCs (if any)
output wire [NUM_VCS-1:0]              sel_op_ivc;

//==============================================================================
// Implementation
//==============================================================================

//---------------------------------------------------------------------------
// global wires
//---------------------------------------------------------------------------

wire [P_NUM_PORTS*P_NUM_PORTS-1:0] req_in_nonspec_ip_op;   
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] req_out_nonspec_ip_op;
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] gnt_out_nonspec_ip_op;

wire [P_NUM_PORTS*P_NUM_PORTS-1:0] req_out_spec_ip_op;
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] gnt_out_spec_ip_op;

wire [P_NUM_PORTS-1:0]             unused_by_nonspec_ip;
wire [P_NUM_PORTS-1:0]             unused_by_nonspec_op;


//---------------------------------------------------------------------------
// input stage
//---------------------------------------------------------------------------

genvar i;

generate for(i = 0; i < P_NUM_PORTS; i = i + 1) begin: INPUT_ARBITER
    
    wire active = active_ip[i];
    wire [NUM_VCS-1:0] route_ivc_op = route_ip_ivc_op[i*NUM_VCS +: NUM_VCS];
    
    //----------------------------------------------------------------------
    // input-side arbitration
    //----------------------------------------------------------------------
    
    wire [P_NUM_PORTS-1:0] 
         gnt_out_nonspec_op = gnt_out_nonspec_ip_op[i*P_NUM_PORTS +: P_NUM_PORTS];
    
    wire gnt_out_nonspec    = |gnt_out_nonspec_op;
    wire update_arb_nonspec =  gnt_out_nonspec;
    
    wire [P_NUM_VCS-1:0] req_nonspec_ivc    = req_nonspec_ip_ivc[i*P_NUM_VCS +: P_NUM_VCS];
    wire [P_NUM_VCS-1:0] req_in_nonspec_ivc = req_nonspec_ivc;
    
    wire [P_NUM_VCS-1:0] gnt_in_nonspec_ivc;
    
    if (P_SPEC_TYPE != `SW_ALLOC_SPEC_TYPE_PRIO) begin: INPUT_SPEC_PRIO_ARBITER
        
        sw_arb_wrapper #(
            .P_NUM_PORTS(P_NUM_VCS),
            .num_priorities(1),
            .P_SW_ARB(P_SW_ARB)
        ) gnt_in_nonspec_ivc_arb (
            .clk(clk),
            .rst_n(rst_n),
            .active(active),
            .update(update_arb_nonspec),
            .req_pr(req_in_nonspec_ivc),
            .gnt_pr(gnt_in_nonspec_ivc),
            .gnt()
        );
    
    end // INPUT_SPEC_PRIO_ARBITER
    
    wire [P_NUM_PORTS-1:0] req_in_nonspec_op;

    c_select_mofn #(
        .width(P_NUM_PORTS),
        .P_NUM_PORTS(P_NUM_VCS)
    ) req_in_nonspec_ip_op_sel (
        .select(req_in_nonspec_ivc),
        .data_in(route_ivc_op),
        .data_out(req_in_nonspec_op)
    );
    
    assign req_in_nonspec_ip_op[i*P_NUM_PORTS +: P_NUM_PORTS] = req_in_nonspec_op;

    //-------------------------------------------------------------------
    // generate requests for output stage
    //-------------------------------------------------------------------
    
    wire [P_NUM_PORTS-1:0] req_out_nonspec_op;

    c_select_mofn #(
        .width(P_NUM_PORTS),
        .P_NUM_PORTS(P_NUM_VCS)
    ) req_out_nonspec_op_sel (
        .select(gnt_in_nonspec_ivc),
        .data_in(route_ivc_op),
        .data_out(req_out_nonspec_op)
    );
    
    assign req_out_nonspec_ip_op[i*P_NUM_PORTS +: P_NUM_PORTS] = req_out_nonspec_op;
    
    //-------------------------------------------------------------------
    // handle speculative requests
    //-------------------------------------------------------------------
    
    wire                   gnt;
    wire [P_NUM_PORTS-1:0] req_out_spec_op;
    wire [P_NUM_VCS-1  :0] sel_ivc;
    
    if(P_SPEC_TYPE != `SW_ALLOC_SPEC_TYPE_NONE) begin: INPUT_SW_ALLOC_SPEC
        
        //--------------------------------------------------------------
        // perform input-side arbitration (speculative)
        //--------------------------------------------------------------

        wire [P_NUM_PORTS-1:0] 
             gnt_out_spec_op = gnt_out_spec_ip_op[i*P_NUM_PORTS +: P_NUM_PORTS];

        wire gnt_out_spec    = |gnt_out_spec_op;
        wire update_arb_spec =  gnt_out_spec;

        wire [P_NUM_VCS-1:0] req_spec_ivc    = req_spec_ip_ivc[i*P_NUM_VCS +: P_NUM_VCS];
        wire [P_NUM_VCS-1:0] req_in_spec_ivc = req_spec_ivc;
 
        wire [P_NUM_VCS-1:0] gnt_in_spec_ivc;
        
        
        if(P_SPEC_TYPE == `SW_ALLOC_SPEC_TYPE_PRIO) begin: INPUT_SW_ALLOC_SPEC_PRIO
            
            wire update_arb = update_arb_spec | update_arb_nonspec;

            sw_arb_wrapper #(
                .P_NUM_PORTS(P_NUM_VCS),
                .num_priorities(2),
                .P_SW_ARB(P_SW_ARB)
            ) gnt_in_ivc_arb (
                .clk(clk),
                .rst_n(rst_n),
                .active(active),
                .update(update_arb),
                .req_pr({req_in_nonspec_ivc, req_in_spec_ivc}),
                .gnt_pr({gnt_in_nonspec_ivc, gnt_in_spec_ivc}),
                .gnt(sel_ivc)
            );

            assign gnt = gnt_out_nonspec | gnt_out_spec;
        
        end: INPUT_SW_ALLOC_SPEC_PRIO
        
        else begin: INPUT_SW_ALLOC_SPEC_NON_PRIO
            
            sw_arb_wrapper #(
                .P_NUM_PORTS(P_NUM_VCS),
                .num_priorities(1),
                .P_SW_ARB(P_SW_ARB)
            ) gnt_in_spec_ivc_arb (
                .clk(clk),
                .rst_n(rst_n),
                .active(active),
                .update(update_arb_spec),
                .req_pr(req_in_spec_ivc),
                .gnt_pr(gnt_in_spec_ivc),
                .gnt()
            );
            
            wire unused_by_nonspec = unused_by_nonspec_ip[i];
            wire [P_NUM_PORTS-1:0] 
                 gnt_out_spec_qual_op = gnt_out_spec_op & unused_by_nonspec_op & {P_NUM_PORTS{unused_by_nonspec}};
                 
            wire gnt_out_spec_qual = |gnt_out_spec_qual_op;
            assign gnt = gnt_out_nonspec | gnt_out_spec_qual;
            
            case(P_SPEC_TYPE)
                `SW_ALLOC_SPEC_TYPE_REQ: begin
                    
                    wire req_nonspec = |req_nonspec_ivc;
                    assign sel_ivc = req_nonspec ? gnt_in_nonspec_ivc : gnt_in_spec_ivc;

                end
                
                `SW_ALLOC_SPEC_TYPE_GNT: begin

                    assign sel_ivc = gnt_out_nonspec ? gnt_in_nonspec_ivc : gnt_in_spec_ivc;

                end
            endcase
        
        end: INPUT_SW_ALLOC_SPEC_NON_PRIO
 
 
        //--------------------------------------------------------------
        // generate requests for output stage (speculative)
        //--------------------------------------------------------------

        c_select_mofn #(
            .width(P_NUM_PORTS),
            .P_NUM_PORTS(P_NUM_VCS)
        ) req_out_spec_op_sel (
            .select(gnt_in_spec_ivc),
            .data_in(route_ivc_op),
            .data_out(req_out_spec_op)
        );

    end: INPUT_SW_ALLOC_SPEC
    
    else begin: SW_ALLOC_NON_SPEC

        assign req_out_spec_op = {P_NUM_PORTS{1'b0}};
        assign sel_ivc         = gnt_in_nonspec_ivc;
        assign gnt             = gnt_out_nonspec;

    end: INPUT_SW_ALLOC_NON_SPEC
    
    
    //-------------------------------------------------------------------
    // combine global grants
    //-------------------------------------------------------------------
    
    assign req_out_spec_ip_op[i*P_NUM_PORTS +: P_NUM_PORTS] = req_out_spec_op;
    assign sel_ip_ivc[i*P_NUM_VCS +: P_NUM_VCS]             = sel_ivc;
    assign gnt_ip[i]                                        = gnt;
       
end: INPUT_ARBITER
   
endgenerate


//---------------------------------------------------------------------------
// bit shuffling for changing sort order
//---------------------------------------------------------------------------

wire [P_NUM_PORTS*P_NUM_PORTS-1:0] req_in_nonspec_op_ip;
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] req_out_nonspec_op_ip;
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] gnt_out_nonspec_op_ip;
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] req_out_spec_op_ip;
wire [P_NUM_PORTS*P_NUM_PORTS-1:0] gnt_out_spec_op_ip;

lib_interleave #(
    .NLANE     (P_NUM_PORTS),
    .WIDTH     (P_NUM_PORTS)
) req_in_nonspec_op_ip_intl (
    .data_in(req_in_nonspec_ip_op )
    .data_out(req_in_nonspec_op_ip)
);

lib_interleave #(
    .NLANE     (P_NUM_PORTS),
    .WIDTH     (P_NUM_PORTS)
) req_out_nonspec_op_ip_intl (
    .data_in(req_out_nonspec_ip_op ),
    .data_out(req_out_nonspec_op_ip)
);

lib_interleave #(
    .NLANE     (P_NUM_PORTS),
    .WIDTH     (P_NUM_PORTS)
) gnt_out_nonspec_op_ip_intl (
    .data_in(gnt_out_nonspec_op_ip),
    .data_out(gnt_out_nonspec_ip_op)
);

lib_interleave #(
    .NLANE     (P_NUM_PORTS),
    .WIDTH     (P_NUM_PORTS)
) req_out_spec_op_ip_intl (
    .data_in(req_out_spec_ip_op),
    .data_out(req_out_spec_op_ip)
);

lib_interleave #(
    .NLANE     (P_NUM_PORTS),
    .WIDTH     (P_NUM_PORTS)
) gnt_out_spec_op_ip_intl (
    .data_in(gnt_out_spec_op_ip),
    .data_out(gnt_out_spec_ip_op)
);


//---------------------------------------------------------------------------
// mask speculative requests that conflict with non-speculative ones
//---------------------------------------------------------------------------

generate case(P_SPEC_TYPE)
    
    `SW_ALLOC_SPEC_TYPE_NONE: 
    begin
        assign unused_by_nonspec_ip = {P_NUM_PORTS{1'b0}};
        assign unused_by_nonspec_op = {P_NUM_PORTS{1'b0}};
    end

    `SW_ALLOC_SPEC_TYPE_PRIO:
    begin
        assign unused_by_nonspec_ip = {P_NUM_PORTS{1'b0}};
        assign unused_by_nonspec_op = {P_NUM_PORTS{1'b0}};
    end

    `SW_ALLOC_SPEC_TYPE_REQ:
    begin:
      
        // We can potentially improve matching by using the grants of the
        // input stage (i.e., the requests of the output stage) to filter 
        // out output ports that have all requests for them eliminated in 
        // the input stage. As the associated OR reduction can be performed
        // in parallel with output-stage arbitration, this should not 
        // increase delay.

        lib_binary_op #(
            .NLANE(P_NUM_PORTS),
            .WIDTH(P_NUM_PORTS),
            .BINOP( "NOR"     )
        ) unused_by_nonspec_op_nor (
            .data_in(req_out_nonspec_ip_op),
            .data_out(unused_by_nonspec_op)
        );
      
        // For determining which inputs are in use, looking at the input-
        // stage grants rather than its requests does not yield any 
        // additional information, as the input-side arbitration stage will
        // generate a grant if and only if there were any requests. Thus,
        // we use the requests here to ease timing.
        lib_binary_op #(
            .NLANE(P_NUM_PORTS),
            .WIDTH(P_NUM_PORTS),
            .BINOP("NOR")
        ) unused_by_nonspec_ip_nor (
            .data_in(req_in_nonspec_op_ip),
            .data_out(unused_by_nonspec_ip)
        );
    
    end //SW_ALLOC_SPEC_TYPE_REQ
    
    `SW_ALLOC_SPEC_TYPE_GNT:
    begin
        
        // An output is granted if and only if there were any output-stage 
        // requests for it; thus, it is sufficient to look at the arbiter 
        // inputs here.
        
        lib_binary_op #(
            .NLANE(P_NUM_PORTS),
            .WIDTH(P_NUM_PORTS),
            .BINOP("NOR")
        ) unused_by_nonspec_op_nor (
            .data_in(req_out_nonspec_ip_op),
            .data_out(unused_by_nonspec_op)
        );
        
        // However, we can make no such simplification to determine which
        // input ports are in use: A given input may have requested 
        // one or more outputs, but all of its requests could have been 
        // eliminated in the output arbitration stage.

        lib_binary_op #(
            .NLANE(P_NUM_PORTS),
            .WIDTH(P_NUM_PORTS),
            .BINOP("NOR")
        ) unused_by_nonspec_ip_nor (
            .data_in(gnt_out_nonspec_op_ip),
            .data_out(unused_by_nonspec_ip)
        );

    end // SW_ALLOC_SPEC_TYPE_GNT

endcase // P_SPEC_TYPE

endgenerate


//---------------------------------------------------------------------------
// output stage
//---------------------------------------------------------------------------

genvar op;

generate for (op = 0; op < P_NUM_PORTS; op = op + 1) begin: OUTPUT_ARBITER
    
    wire active = active_op[op];
    
    //-------------------------------------------------------------------
    // perform output-side arbitration (select input port)
    //-------------------------------------------------------------------
    
    wire [P_NUM_PORTS-1:0] sel_ip;
    wire [P_NUM_PORTS-1:0] req_out_nonspec_ip = 
                             req_out_nonspec_op_ip[op*P_NUM_PORTS +: P_NUM_PORTS];
    
    wire req_out_nonspec = |req_out_nonspec_ip;
    
    // if any VC requesting this output port was granted at any input
    // port in the first stage, one of these input ports will be granted
    // here as well, and we can thus update priorities
    
    wire update_arb_nonspec = req_out_nonspec;
    
    wire [P_NUM_PORTS-1:0] gnt_out_nonspec_ip;
    
    if(P_SPEC_TYPE != `SW_ALLOC_SPEC_TYPE_PRIO) begin: OUTPUT_SW_ALLOC_PRIO_ARB
        
        sw_arb_wrapper #(
            .P_NUM_PORTS(P_NUM_PORTS),
            .num_priorities(1),
            .P_SW_ARB(P_SW_ARB)
        ) gnt_out_nonspec_ip_arb (
            .clk(clk),
            .rst_n(rst_n),
            .active(active),
            .update(update_arb_nonspec),
            .req_pr(req_out_nonspec_ip),
            .gnt_pr(gnt_out_nonspec_ip),
            .gnt()
        );
    
    end: OUTPUT_SW_ALLOC_PRIO_ARB
    
    
    //-------------------------------------------------------------------
    // handle speculative requests
    //-------------------------------------------------------------------
    
    wire [P_NUM_PORTS-1:0] gnt_out_spec_ip;
    wire gnt;
    
    if(P_SPEC_TYPE != `SW_ALLOC_SPEC_TYPE_NONE) begin: OUTPUT_SW_ALLOC_SPEC
 
        //--------------------------------------------------------------
        // perform output-side arbitration (speculative)
        //--------------------------------------------------------------
    
        wire [P_NUM_PORTS-1:0] req_out_spec_ip = req_out_spec_op_ip[op*P_NUM_PORTS +: P_NUM_PORTS];
        wire req_out_spec    = |req_out_spec_ip;
        wire update_arb_spec =  req_out_spec;
    
        if(P_SPEC_TYPE == `SW_ALLOC_SPEC_TYPE_PRIO) begin: OUTPUT_SW_ALLOC_SPEC_PRIO_ARB
            
            wire update_arb = update_arb_nonspec | update_arb_spec;
        
            sw_arb_wrapper #(
                .P_NUM_PORTS(P_NUM_PORTS),
                .num_priorities(2),
                .P_SW_ARB(P_SW_ARB),
            ) gnt_out_ip_arb (
                .clk(clk),
                .rst_n(rst_n),
                .active(active),
                .update(update_arb),
                .req_pr({req_out_nonspec_ip, req_out_spec_ip}),
                .gnt_pr({gnt_out_nonspec_ip, gnt_out_spec_ip}),
                .gnt(sel_ip)
            );
     
            assign gnt = req_out_nonspec | req_out_spec;

        end // OUTPUT_SW_ALLOC_SPEC_PRIO_ARB
        
        else begin: OUTPUT_SW_ALLOC_SPEC_NON_PRIO_ARB
        
            sw_arb_wrapper #(
                .P_NUM_PORTS(P_NUM_PORTS),
                .num_priorities(1),
                .P_SW_ARB(P_SW_ARB),
            ) gnt_out_spec_ip_arb (
                .clk(clk),
                .rst_n(rst_n),
                .active(active),
                .update(update_arb_spec),
                .req_pr(req_out_spec_ip),
                .gnt_pr(gnt_out_spec_ip),
                .gnt()
            );
            
            wire unused_by_nonspec    = unused_by_nonspec_op[op];
            wire [P_NUM_PORTS-1:0] 
                 gnt_out_spec_qual_ip = gnt_out_spec_ip & unused_by_nonspec_ip & {P_NUM_PORTS{unused_by_nonspec}};
                 
            wire   gnt_out_spec_qual  = |gnt_out_spec_qual_ip;
            
            assign sel_ip = gnt_out_nonspec_ip | gnt_out_spec_qual_ip;
            assign gnt    = req_out_nonspec    | gnt_out_spec_qual;
        
        end // OUTPUT_SW_ALLOC_SPEC_NON_PRIO_ARB
    
    end // OUTPUT_SW_ALLOC_SPEC
 
    else begin: OUTPUT_SW_ALLOC_NON_SPEC
        
        assign gnt_out_spec_ip = {P_NUM_PORTS{1'b0}};
        assign gnt             = req_out_nonspec;
        assign sel_ip          = gnt_out_nonspec_ip;
    
    end // OUTPUT_SW_ALLOC_NON_SPEC
    
    
    
    wire [P_NUM_VCS-1:0] sel_ivc;
    
    lib_mux #(
        .NLANE(P_NUM_PORTS)
        .WIDTH(P_NUM_VCS)
    ) sel_ivc_sel (
        .sel(sel_ip),
        .in(sel_ip_ivc),
        .de({P_NUM_VCS{1'b0}}),
        .out(sel_ivc)
    );
    
    assign gnt_out_nonspec_op_ip[op*P_NUM_PORTS +: P_NUM_PORTS] = gnt_out_nonspec_ip;
    assign gnt_out_spec_op_ip[op*P_NUM_PORTS +: P_NUM_PORTS]    = gnt_out_spec_ip;
    assign gnt_op[op]                                           = gnt;
    assign sel_op_ip[op*P_NUM_PORTS +: P_NUM_PORTS]             = sel_ip;
    assign sel_op_ivc[op*P_NUM_VCS +: P_NUM_VCS]                = sel_ivc;
    
end // OUTPUT_ARBITER
   
endgenerate

endmodule
