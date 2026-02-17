#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

ALL_TESTS="
	skb_mark_filter
	skb_tc_index_filter
	skb_priority_filter
"

NUM_NETIFS=4
CHECK_TC="yes"
source lib.sh

h1_create()
{
	simple_if_init $h1 192.0.2.1/28 2001:db8:1::1/64
}

h1_destroy()
{
	simple_if_fini $h1 192.0.2.1/28 2001:db8:1::1/64
}

h2_create()
{
	simple_if_init $h2 192.0.2.2/28 2001:db8:1::2/64
}

h2_destroy()
{
	simple_if_fini $h2 192.0.2.2/28 2001:db8:1::2/64
}

switch_create()
{
	ip link add dev br0 type bridge vlan_filtering 1 mcast_snooping 0

	ip link set dev $swp1 master br0
	ip link set dev $swp2 master br0

	ip link set dev br0 up
	ip link set dev $swp1 up
	ip link set dev $swp2 up

	tc qdisc add dev $swp1 clsact
	tc qdisc add dev $swp2 clsact
}

switch_destroy()
{
	tc qdisc del dev $swp2 clsact
	tc qdisc del dev $swp1 clsact

	ip link set dev $swp2 down
	ip link set dev $swp1 down

	ip link del dev br0
}

setup_prepare()
{
	h1=${NETIFS[p1]}
	swp1=${NETIFS[p2]}

	swp2=${NETIFS[p3]}
	h2=${NETIFS[p4]}

	vrf_prepare

	h1_create
	h2_create

	switch_create
}

cleanup()
{
	pre_cleanup

	switch_destroy

	h2_destroy
	h1_destroy

	vrf_cleanup
}

skb_mark_filter()
{
	RET=0

	tc filter add dev $swp1 ingress protocol all pref 1 handle 1 \
	   flower action skbedit mark 1234
	tc filter add dev $swp2 egress protocol all pref 2 handle 1 \
	   flower action drop

	ping_do $h1 192.0.2.2
	check_fail $? "traffic was not dropped as expected"

	ping6_do $h1 2001:db8:1::2
	check_fail $? "traffic was not dropped as expected (IPv6)"

	tc filter add dev $swp2 egress protocol all pref 1 handle 1 \
		flower mark 1234 action pass

	ping_do $h1 192.0.2.2
	check_err $? "ping between two ports failed when should not"

	ping6_do $h1 2001:db8:1::2
	check_err $? "ping6 between two different ports failed when should not"

	log_test "skb mark filter on skb->mark"

	tc filter del dev $swp2 egress protocol all pref 1 handle 1 flower
	tc filter del dev $swp2 egress protocol all pref 2 handle 1 flower
	tc filter del dev $swp1 ingress protocol all pref 1 handle 1 flower

}

skb_tc_index_filter()
{
	RET=0

	# The flower classifier sets skb->tc_index to TC_H_MIN(classid)
	# on TC_ACT_OK. classid 0:4d2 gives tc_index 0x4d2 = 1234.
	tc filter add dev $swp1 ingress protocol all pref 1 handle 1 \
	   flower classid 0:4d2 action pass
	tc filter add dev $swp2 egress protocol all pref 2 handle 1 \
	   flower action drop

	ping_do $h1 192.0.2.2
	check_fail $? "traffic was not dropped as expected"

	ping6_do $h1 2001:db8:1::2
	check_fail $? "traffic was not dropped as expected (IPv6)"

	tc filter add dev $swp2 egress protocol all pref 1 handle 1 \
		flower tc_index 1234 action pass

	ping_do $h1 192.0.2.2
	check_err $? "ping between two ports failed when should not"

	ping6_do $h1 2001:db8:1::2
	check_err $? "ping6 between two different ports failed when should not"

	log_test "skb tc_index filter on skb->tc_index"

	tc filter del dev $swp2 egress protocol all pref 1 handle 1 flower
	tc filter del dev $swp2 egress protocol all pref 2 handle 1 flower
	tc filter del dev $swp1 ingress protocol all pref 1 handle 1 flower
}

skb_priority_filter()
{
	RET=0

	tc filter add dev $swp1 ingress protocol all pref 1 handle 1 \
	   flower action skbedit priority 7
	tc filter add dev $swp2 egress protocol all pref 2 handle 1 \
	   flower action drop

	ping_do $h1 192.0.2.2
	check_fail $? "traffic was not dropped as expected"

	ping6_do $h1 2001:db8:1::2
	check_fail $? "traffic was not dropped as expected (IPv6)"

	tc filter add dev $swp2 egress protocol all pref 1 handle 1 \
		flower priority 7 action pass

	ping_do $h1 192.0.2.2
	check_err $? "ping between two ports failed when should not"

	ping6_do $h1 2001:db8:1::2
	check_err $? "ping6 between two different ports failed when should not"

	log_test "skb priority filter on skb->priority"

	tc filter del dev $swp2 egress protocol all pref 1 handle 1 flower
	tc filter del dev $swp2 egress protocol all pref 2 handle 1 flower
	tc filter del dev $swp1 ingress protocol all pref 1 handle 1 flower
}

trap cleanup EXIT

setup_prepare
setup_wait

tests_run

exit $EXIT_STATUS
