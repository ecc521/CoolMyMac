import Foundation
import Darwin

func queryPID(_ pid: Int32) {
    var taskInfo = proc_taskinfo()
    let size = MemoryLayout<proc_taskinfo>.size
    let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size))
    if result <= 0 {
        print("Failed to query PID \(pid), result: \(result)")
        return
    }
    print("PID: \(pid)")
    print("Virtual Size: \(taskInfo.pti_virtual_size)")
    print("Resident Size: \(taskInfo.pti_resident_size)")
    print("Total User Time (ns): \(taskInfo.pti_total_user)")
    print("Total System Time (ns): \(taskInfo.pti_total_system)")
    print("Default Policy: \(taskInfo.pti_policy)")
    print("Thread Num: \(taskInfo.pti_threadnum)")
    print("Num Running Threads: \(taskInfo.pti_numrunning)")
    print("Priority: \(taskInfo.pti_priority)")
}

let arguments = CommandLine.arguments
if arguments.count > 1, let pid = Int32(arguments[1]) {
    queryPID(pid)
} else {
    queryPID(45396)
}
