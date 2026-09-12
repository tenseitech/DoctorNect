import re
import os

import sys; log_path = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\hp\.gemini\antigravity\brain\74ebfb83-ea21-4d10-8135-6719ed185446\.system_generated\tasks\task-375.log"

with open(log_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for line in lines:
    if "error -" in line and ("const_eval_method_invocation" in line or "undefined_identifier" in line):
        match = re.search(r'- ([a-zA-Z0-9_\.\\\/]+):(\d+):\d+ - (const_eval_method_invocation|undefined_identifier)', line)
        if match:
            filepath = match.group(1).strip()
            linenum = int(match.group(2))
            error_type = match.group(3)
            
            if not os.path.exists(filepath):
                print(f"File not found: {filepath}")
                continue
                
            with open(filepath, 'r', encoding='utf-8') as src:
                src_lines = src.readlines()
                
            idx = linenum - 1
            if error_type == 'undefined_identifier':
                src_lines[idx] = src_lines[idx].replace('AppColors.surfaceOf(context)', 'Colors.white')
                src_lines[idx] = src_lines[idx].replace('AppColors.cardBgOf(context)', 'AppColors.cardBackground')
                src_lines[idx] = src_lines[idx].replace('AppColors.textPrimaryOf(context)', 'AppColors.textPrimary')
                src_lines[idx] = src_lines[idx].replace('AppColors.textSecondaryOf(context)', 'AppColors.textSecondary')
                src_lines[idx] = src_lines[idx].replace('AppColors.borderOf(context)', 'AppColors.border')
                
            elif error_type == 'const_eval_method_invocation':
                for i in range(idx, max(-1, idx - 10), -1):
                    if 'const ' in src_lines[i]:
                        # Use regex to only replace whole word 'const '
                        src_lines[i] = re.sub(r'\bconst\s+', '', src_lines[i], count=1)
                        break
                        
            with open(filepath, 'w', encoding='utf-8') as src:
                src.writelines(src_lines)
