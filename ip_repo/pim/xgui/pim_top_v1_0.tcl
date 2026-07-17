# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "PIM_BANK_NUM_BANKS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PIM_CMD_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SHARED_BUFF_DATA_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.ACC_REGS_ADDR_WIDTH { PARAM_VALUE.ACC_REGS_ADDR_WIDTH } {
	# Procedure called to update ACC_REGS_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ACC_REGS_ADDR_WIDTH { PARAM_VALUE.ACC_REGS_ADDR_WIDTH } {
	# Procedure called to validate ACC_REGS_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.EW_MUL_BANK_GROUPS { PARAM_VALUE.EW_MUL_BANK_GROUPS } {
	# Procedure called to update EW_MUL_BANK_GROUPS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.EW_MUL_BANK_GROUPS { PARAM_VALUE.EW_MUL_BANK_GROUPS } {
	# Procedure called to validate EW_MUL_BANK_GROUPS
	return true
}

proc update_PARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH { PARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH } {
	# Procedure called to update GLOBAL_BUFF_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH { PARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH } {
	# Procedure called to validate GLOBAL_BUFF_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH { PARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH } {
	# Procedure called to update GLOBAL_BUFF_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH { PARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH } {
	# Procedure called to validate GLOBAL_BUFF_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.MAC_INPUT_LANE_WIDTH { PARAM_VALUE.MAC_INPUT_LANE_WIDTH } {
	# Procedure called to update MAC_INPUT_LANE_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAC_INPUT_LANE_WIDTH { PARAM_VALUE.MAC_INPUT_LANE_WIDTH } {
	# Procedure called to validate MAC_INPUT_LANE_WIDTH
	return true
}

proc update_PARAM_VALUE.MAC_LANE_NUMS { PARAM_VALUE.MAC_LANE_NUMS } {
	# Procedure called to update MAC_LANE_NUMS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAC_LANE_NUMS { PARAM_VALUE.MAC_LANE_NUMS } {
	# Procedure called to validate MAC_LANE_NUMS
	return true
}

proc update_PARAM_VALUE.MAC_RESULT_LANE_WIDTH { PARAM_VALUE.MAC_RESULT_LANE_WIDTH } {
	# Procedure called to update MAC_RESULT_LANE_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAC_RESULT_LANE_WIDTH { PARAM_VALUE.MAC_RESULT_LANE_WIDTH } {
	# Procedure called to validate MAC_RESULT_LANE_WIDTH
	return true
}

proc update_PARAM_VALUE.PIM_BANK_ADDR_WIDTH { PARAM_VALUE.PIM_BANK_ADDR_WIDTH } {
	# Procedure called to update PIM_BANK_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIM_BANK_ADDR_WIDTH { PARAM_VALUE.PIM_BANK_ADDR_WIDTH } {
	# Procedure called to validate PIM_BANK_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.PIM_BANK_LANE_NUMS { PARAM_VALUE.PIM_BANK_LANE_NUMS } {
	# Procedure called to update PIM_BANK_LANE_NUMS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIM_BANK_LANE_NUMS { PARAM_VALUE.PIM_BANK_LANE_NUMS } {
	# Procedure called to validate PIM_BANK_LANE_NUMS
	return true
}

proc update_PARAM_VALUE.PIM_BANK_LANE_WIDTH { PARAM_VALUE.PIM_BANK_LANE_WIDTH } {
	# Procedure called to update PIM_BANK_LANE_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIM_BANK_LANE_WIDTH { PARAM_VALUE.PIM_BANK_LANE_WIDTH } {
	# Procedure called to validate PIM_BANK_LANE_WIDTH
	return true
}

proc update_PARAM_VALUE.PIM_BANK_NUM_BANKS { PARAM_VALUE.PIM_BANK_NUM_BANKS } {
	# Procedure called to update PIM_BANK_NUM_BANKS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIM_BANK_NUM_BANKS { PARAM_VALUE.PIM_BANK_NUM_BANKS } {
	# Procedure called to validate PIM_BANK_NUM_BANKS
	return true
}

proc update_PARAM_VALUE.PIM_CMD_WIDTH { PARAM_VALUE.PIM_CMD_WIDTH } {
	# Procedure called to update PIM_CMD_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIM_CMD_WIDTH { PARAM_VALUE.PIM_CMD_WIDTH } {
	# Procedure called to validate PIM_CMD_WIDTH
	return true
}

proc update_PARAM_VALUE.SHARED_BUFF_ADDR_WIDTH { PARAM_VALUE.SHARED_BUFF_ADDR_WIDTH } {
	# Procedure called to update SHARED_BUFF_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SHARED_BUFF_ADDR_WIDTH { PARAM_VALUE.SHARED_BUFF_ADDR_WIDTH } {
	# Procedure called to validate SHARED_BUFF_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.SHARED_BUFF_DATA_WIDTH { PARAM_VALUE.SHARED_BUFF_DATA_WIDTH } {
	# Procedure called to update SHARED_BUFF_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SHARED_BUFF_DATA_WIDTH { PARAM_VALUE.SHARED_BUFF_DATA_WIDTH } {
	# Procedure called to validate SHARED_BUFF_DATA_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.SHARED_BUFF_DATA_WIDTH { MODELPARAM_VALUE.SHARED_BUFF_DATA_WIDTH PARAM_VALUE.SHARED_BUFF_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SHARED_BUFF_DATA_WIDTH}] ${MODELPARAM_VALUE.SHARED_BUFF_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.PIM_CMD_WIDTH { MODELPARAM_VALUE.PIM_CMD_WIDTH PARAM_VALUE.PIM_CMD_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIM_CMD_WIDTH}] ${MODELPARAM_VALUE.PIM_CMD_WIDTH}
}

proc update_MODELPARAM_VALUE.SHARED_BUFF_ADDR_WIDTH { MODELPARAM_VALUE.SHARED_BUFF_ADDR_WIDTH PARAM_VALUE.SHARED_BUFF_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SHARED_BUFF_ADDR_WIDTH}] ${MODELPARAM_VALUE.SHARED_BUFF_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH { MODELPARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH PARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH}] ${MODELPARAM_VALUE.GLOBAL_BUFF_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH { MODELPARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH PARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH}] ${MODELPARAM_VALUE.GLOBAL_BUFF_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.PIM_BANK_NUM_BANKS { MODELPARAM_VALUE.PIM_BANK_NUM_BANKS PARAM_VALUE.PIM_BANK_NUM_BANKS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIM_BANK_NUM_BANKS}] ${MODELPARAM_VALUE.PIM_BANK_NUM_BANKS}
}

proc update_MODELPARAM_VALUE.PIM_BANK_ADDR_WIDTH { MODELPARAM_VALUE.PIM_BANK_ADDR_WIDTH PARAM_VALUE.PIM_BANK_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIM_BANK_ADDR_WIDTH}] ${MODELPARAM_VALUE.PIM_BANK_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.MAC_INPUT_LANE_WIDTH { MODELPARAM_VALUE.MAC_INPUT_LANE_WIDTH PARAM_VALUE.MAC_INPUT_LANE_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAC_INPUT_LANE_WIDTH}] ${MODELPARAM_VALUE.MAC_INPUT_LANE_WIDTH}
}

proc update_MODELPARAM_VALUE.MAC_RESULT_LANE_WIDTH { MODELPARAM_VALUE.MAC_RESULT_LANE_WIDTH PARAM_VALUE.MAC_RESULT_LANE_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAC_RESULT_LANE_WIDTH}] ${MODELPARAM_VALUE.MAC_RESULT_LANE_WIDTH}
}

proc update_MODELPARAM_VALUE.EW_MUL_BANK_GROUPS { MODELPARAM_VALUE.EW_MUL_BANK_GROUPS PARAM_VALUE.EW_MUL_BANK_GROUPS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.EW_MUL_BANK_GROUPS}] ${MODELPARAM_VALUE.EW_MUL_BANK_GROUPS}
}

proc update_MODELPARAM_VALUE.MAC_LANE_NUMS { MODELPARAM_VALUE.MAC_LANE_NUMS PARAM_VALUE.MAC_LANE_NUMS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAC_LANE_NUMS}] ${MODELPARAM_VALUE.MAC_LANE_NUMS}
}

proc update_MODELPARAM_VALUE.PIM_BANK_LANE_NUMS { MODELPARAM_VALUE.PIM_BANK_LANE_NUMS PARAM_VALUE.PIM_BANK_LANE_NUMS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIM_BANK_LANE_NUMS}] ${MODELPARAM_VALUE.PIM_BANK_LANE_NUMS}
}

proc update_MODELPARAM_VALUE.PIM_BANK_LANE_WIDTH { MODELPARAM_VALUE.PIM_BANK_LANE_WIDTH PARAM_VALUE.PIM_BANK_LANE_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIM_BANK_LANE_WIDTH}] ${MODELPARAM_VALUE.PIM_BANK_LANE_WIDTH}
}

proc update_MODELPARAM_VALUE.ACC_REGS_ADDR_WIDTH { MODELPARAM_VALUE.ACC_REGS_ADDR_WIDTH PARAM_VALUE.ACC_REGS_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ACC_REGS_ADDR_WIDTH}] ${MODELPARAM_VALUE.ACC_REGS_ADDR_WIDTH}
}

