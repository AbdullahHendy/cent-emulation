# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "INSTR_BUFF_ADDR_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.DEC_INSTR_WIDTH { PARAM_VALUE.DEC_INSTR_WIDTH } {
	# Procedure called to update DEC_INSTR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEC_INSTR_WIDTH { PARAM_VALUE.DEC_INSTR_WIDTH } {
	# Procedure called to validate DEC_INSTR_WIDTH
	return true
}

proc update_PARAM_VALUE.INSTR_BUFF_ADDR_WIDTH { PARAM_VALUE.INSTR_BUFF_ADDR_WIDTH } {
	# Procedure called to update INSTR_BUFF_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INSTR_BUFF_ADDR_WIDTH { PARAM_VALUE.INSTR_BUFF_ADDR_WIDTH } {
	# Procedure called to validate INSTR_BUFF_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.INSTR_BUFF_DATA_WIDTH { PARAM_VALUE.INSTR_BUFF_DATA_WIDTH } {
	# Procedure called to update INSTR_BUFF_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INSTR_BUFF_DATA_WIDTH { PARAM_VALUE.INSTR_BUFF_DATA_WIDTH } {
	# Procedure called to validate INSTR_BUFF_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.OTHER_DATA_WIDTH { PARAM_VALUE.OTHER_DATA_WIDTH } {
	# Procedure called to update OTHER_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OTHER_DATA_WIDTH { PARAM_VALUE.OTHER_DATA_WIDTH } {
	# Procedure called to validate OTHER_DATA_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.INSTR_BUFF_ADDR_WIDTH { MODELPARAM_VALUE.INSTR_BUFF_ADDR_WIDTH PARAM_VALUE.INSTR_BUFF_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INSTR_BUFF_ADDR_WIDTH}] ${MODELPARAM_VALUE.INSTR_BUFF_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.INSTR_BUFF_DATA_WIDTH { MODELPARAM_VALUE.INSTR_BUFF_DATA_WIDTH PARAM_VALUE.INSTR_BUFF_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INSTR_BUFF_DATA_WIDTH}] ${MODELPARAM_VALUE.INSTR_BUFF_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.OTHER_DATA_WIDTH { MODELPARAM_VALUE.OTHER_DATA_WIDTH PARAM_VALUE.OTHER_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OTHER_DATA_WIDTH}] ${MODELPARAM_VALUE.OTHER_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.DEC_INSTR_WIDTH { MODELPARAM_VALUE.DEC_INSTR_WIDTH PARAM_VALUE.DEC_INSTR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEC_INSTR_WIDTH}] ${MODELPARAM_VALUE.DEC_INSTR_WIDTH}
}

