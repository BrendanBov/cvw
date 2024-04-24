# David_Harris@hmc.edu 2023
# Top-level Makefile for CORE-V-Wally
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

all:
	make install
	make riscof	
	make testfloat
#	make verify
	make coverage
	make benchmarks

# install copies over the Makefile.include from riscv-isa-sim
# And corrects the TARGETDIR path and the RISCV_PREFIX

install:
	# *** 1/15/23 dh: check if any of this is still needed
	#cp ${RISCV}/riscv-isa-sim/arch_test_target/spike/Makefile.include addins/riscv-arch-test/
	#sed -i '/export TARGETDIR ?=/c\export TARGETDIR ?= ${RISCV}/riscv-isa-sim/arch_test_target' addins/riscv-arch-test/Makefile.include
	#echo export RISCV_PREFIX = riscv64-unknown-elf- >> addins/riscv-arch-test/Makefile.include
	##cd tests/linux-testgen/linux-testvectors; source ./tvLinker.sh # needs to be run in local directory
	##rm tests/imperas-riscv-tests/riscv-ovpsim-plus/bin/Linux64/riscvOVPsimPlus.exe
	##ln -s ${RISCV}/imperas-riscv-tests/riscv-ovpsim-plus/bin/Linux64/riscvOVPsimPlus.exe tests/imperas-riscv-tests/riscv-ovpsim-plus/bin/Linux64/riscvOVPsimPlus.exe

riscof:
	make -C sim

testfloat:
	cd ${WALLY}/addins/SoftFloat-3e/build/Linux-x86_64-GCC; make
	cd ${WALLY}/addins/TestFloat-3e/build/Linux-x86_64-GCC; make
	cd ${WALLY}/tests/fp; ./create_all_vectors.sh

verify:
	cd ${WALLY}/sim; ./regression-wally
	cd ${WALLY}/sim; ./sim-testfloat-batch all
	make imperasdv

imperasdv:
	iter-elf.bash --search ${WALLY}/tests/riscof/work/wally-riscv-arch-test/rv64i_m
	iter-elf.bash --search ${WALLY}/tests/riscof/work/riscv-arch-test/rv64i_m

imperasdv_cov:
	touch ${WALLY}/sim/seed0.txt
	echo "0" > ${WALLY}/sim/seed0.txt
#	/opt/riscv/ImperasDV-OpenHW/scripts/cvw/run-elf-cov.bash --verbose --seed 0 --search ${WALLY}/tests/riscof/work/wally-riscv-arch-test/rv64i_m
#	/opt/riscv/ImperasDV-OpenHW/scripts/cvw/run-elf-cov.bash --elf ${WALLY}/tests/riscof/work/riscv-arch-test/rv64i_m/I/src/add-01.S/dut/my.elf --seed ${WALLY}/sim/seed0.txt --coverdb ${WALLY}/sim/cov/rv64gc_arch64i.ucdb --verbose
#	/opt/riscv/ImperasDV-OpenHW/scripts/cvw/run-elf-cov.bash --elf ${WALLY}/tests/riscof/work/riscv-arch-test/rv64i_m/I/src/add-01.S/dut/my.elf --seed ${WALLY}/sim/seed0.txt --coverdb riscv.ucdb --verbose
	run-elf-cov.bash --elf ${WALLY}/tests/output_folder/asm_test/riscv_arithmetic_basic_test_0.elf --seed ${WALLY}/sim/seed0.txt --coverdb riscv.ucdb --verbose
	vcover report -details -html sim/riscv.ucdb

funcovreg:
	#iter-elf.bash --search ${WALLY}/tests/riscof/work/wally-riscv-arch-test/rv64i_m --cover
	#iter-elf.bash --search ${WALLY}/tests/riscof/work/wally-riscv-arch-test/rv64i_m/I --cover
	#iter-elf.bash --search ${WALLY}/tests/riscof/work/wally-riscv-arch-test/rv64i_m/privilege --cover
	#iter-elf.bash --search ${WALLY}/tests/riscof/work/wally-riscv-arch-test/rv64i_m/Q --cover
	rm -f ${WALLY}/tests/riscof/work/riscv-arch-test/rv64i_m/*/src/*/dut/my.elf
	iter-elf.bash --search ${WALLY}/tests/riscof/work/riscv-arch-test/rv64i_m/I --cover
	vcover report -details -html sim/riscv.ucdb

# test_name=riscv_arithmetic_basic_test
rvdv: 
	python3 ${WALLY}/addins/riscv-dv/run.py --test ${test_name} --target rv64gc --output tests/output_folder  --iterations 1 -si questa --iss spike --verbose --cov --seed 0 --steps gen			>> sim/regression_logs/${test_name}.log 2>&1
	python3 ${WALLY}/addins/riscv-dv/run.py --test ${test_name} --target rv64gc --output tests/output_folder  --iterations 1 -si questa --iss spike --verbose --cov --seed 0 --steps gcc_compile	>> sim/regression_logs/${test_name}.log 2>&1
	python3 ${WALLY}/addins/riscv-dv/run.py --test ${test_name} --target rv64gc --output tests/output_folder  --iterations 1 -si questa --iss spike --verbose --cov --seed 0 --steps iss_sim		>> sim/regression_logs/${test_name}.log 2>&1
#	run-elf.bash --seed ${WALLY}/sim/seed0.txt --verbose --elf ${WALLY}/tests/output_folder/asm_test/${test_name}_0.o													>> sim/regression_logs/${test_name}.log 2>&1
	run-elf-cov.bash --seed ${WALLY}/sim/seed0.txt --verbose --coverdb sim/riscv.ucdb --elf ${WALLY}/tests/output_folder/asm_test/${test_name}_0.o								>> sim/regression_logs/${test_name}.log 2>&1
	cp sim/riscv.ucdb sim/regression_ucdbs/${test_name}.ucdb

rvdv_regression:
	mkdir -p sim/regression_logs
	mkdir -p sim/regression_ucdbs
	cd sim/regression_logs && rm -rf *
	cd sim/regression_ucdbs && rm -rf *
	make rvdv test_name=riscv_arithmetic_basic_test				>> sim/regression.log 2>&1
	make rvdv test_name=riscv_amo_test							>> sim/regression.log 2>&1
	make rvdv test_name=riscv_ebreak_debug_mode_test			>> sim/regression.log 2>&1
	make rvdv test_name=riscv_ebreak_test						>> sim/regression.log 2>&1
	make rvdv test_name=riscv_floating_point_arithmetic_test	>> sim/regression.log 2>&1
	make rvdv test_name=riscv_floating_point_mmu_stress_test	>> sim/regression.log 2>&1
	make rvdv test_name=riscv_floating_point_rand_test			>> sim/regression.log 2>&1
	make rvdv test_name=riscv_full_interrupt_test				>> sim/regression.log 2>&1
	make rvdv test_name=riscv_hint_instr_test					>> sim/regression.log 2>&1
	make rvdv test_name=riscv_illegal_instr_test				>> sim/regression.log 2>&1
	make rvdv test_name=riscv_invalid_csr_test					>> sim/regression.log 2>&1
	make rvdv test_name=riscv_jump_stress_test					>> sim/regression.log 2>&1
	make rvdv test_name=riscv_loop_test							>> sim/regression.log 2>&1
	make rvdv test_name=riscv_machine_mode_rand_test			>> sim/regression.log 2>&1
	make rvdv test_name=riscv_mmu_stress_test					>> sim/regression.log 2>&1
	make rvdv test_name=riscv_no_fence_test						>> sim/regression.log 2>&1
	make rvdv test_name=riscv_non_compressed_instr_test			>> sim/regression.log 2>&1
	make rvdv test_name=riscv_pmp_test							>> sim/regression.log 2>&1
	make rvdv test_name=riscv_privileged_mode_rand_test			>> sim/regression.log 2>&1
	make rvdv test_name=riscv_rand_instr_test					>> sim/regression.log 2>&1
	make rvdv test_name=riscv_rand_jump_test					>> sim/regression.log 2>&1
	make rvdv test_name=riscv_sfence_exception_test				>> sim/regression.log 2>&1
	make rvdv test_name=riscv_unaligned_load_store_test			>> sim/regression.log 2>&1

rvdv_combine_coverage:
	mkdir -p sim/regcov
	cd sim/regcov && rm -rf *
	vcover merge sim/regcov/regcov.ucdb  sim/regression_ucdbs/* -suppress 6854 -64
	vcover report -details -html sim/regcov/regcov.ucdb
	vcover report sim/regcov/regcov.ucdb -details -cvg > sim/regcov/regcov.ucdb.log
	vcover report sim/regcov/regcov.ucdb -testdetails -cvg > sim/regcov/regcov.ucdb.testdetails.log
	vcover report sim/regcov/regcov.ucdb -details -cvg -below 100 | egrep "Coverpoint|Covergroup|Cross" | grep -v Metric > sim/regcov/regcov.ucdb.summary.log
	grep "Total Coverage By Instance" sim/regcov/regcov.ucdb.log

remove_rvdv_artifacts:
	rm sim/riscv.ucdb sim/regression.log covhtmlreport/ sim/regression_logs/ sim/regression_ucdbs/ sim/regcov/ -rf

collect_riscvdv_regression_coverage: remove_rvdv_artifacts rvdv_regression rvdv_combine_coverage
coverage:
	regression-wally -coverage -fp

benchmarks:
	make coremark
	make embench

coremark:
	cd ${WALLY}/benchmarks/coremark; make; make run

embench:
	cd ${WALLY}/benchmarks/embench; make; make run


clean:
	make clean -C sim

