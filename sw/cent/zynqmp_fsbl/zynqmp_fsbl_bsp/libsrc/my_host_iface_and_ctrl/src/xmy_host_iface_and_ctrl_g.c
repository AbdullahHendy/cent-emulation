#include "xmy_host_iface_and_ctrl.h"

XMy_host_iface_and_ctrl_Config XMy_host_iface_and_ctrl_ConfigTable[] __attribute__ ((section (".drvcfg_sec"))) = {

	{
		"xlnx,my-host-iface-and-ctrl-1.0", /* compatible */
		0xa0000000, /* reg */
		0x4059, /* interrupts */
		0xf9010000 /* interrupt-parent */
	},
	 {
		 NULL
	}
};