/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_beat.sv
 Module/class Name             : stream_beat
 Author                        : Vijay Bogati
 Description                   : Single accepted beat (valid & ready) published by the stream monitor with its sample time
***************************************************************/
`ifndef STREAM_BEAT_SV
`define STREAM_BEAT_SV

class stream_beat extends uvm_sequence_item;
  `uvm_object_utils(stream_beat)

  bit [31:0] data;
  bit        last;
  bit        first;   // first beat of a packet (header)
  time       stamp;   // clock edge at which the handshake completed

  function new(string name = "stream_beat");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("beat data=0x%08h last=%0b first=%0b @%0t", data, last, first, stamp);
  endfunction

endclass : stream_beat

`endif
