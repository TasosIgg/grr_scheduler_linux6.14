#include <stdio.h>
#include <unistd.h>

void burn_cpu() {
    volatile unsigned long i = 0;
    while (1) {
        i++;
        if (i == 1000000000UL) i = 0;  
    }
}

int main() {
    fflush(stdout); 
    burn_cpu();
    return 0;  
}
