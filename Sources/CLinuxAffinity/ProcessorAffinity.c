/*
 * Copyright IBM Corporation 2018
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifdef __linux__

#define _GNU_SOURCE
#include <sched.h>
#include <unistd.h>

// Reference: https://stackoverflow.com/questions/10490756/how-to-use-sched-getaffinity-and-sched-setaffinity-in-linux-from-c
int linux_sched_getaffinity() {
    cpu_set_t mask;
    long nproc, i, count = 0;

    if (sched_getaffinity(0, sizeof(cpu_set_t), &mask) == -1) {
        return -1;
    } else {
        nproc = sysconf(_SC_NPROCESSORS_ONLN);
        for (i = 0; i < nproc; i++) {
            if(CPU_ISSET(i, &mask))
                count += 1;
        }
        return count;
    }
}

#endif
