import os
import sys

def main():
    if len(sys.argv) != 2:
        print("Usage: python table_detection.py <string_to_save>")
        sys.exit(1)

    string_to_save = sys.argv[1]
    output_dir = "/pvc/benchmark_results/table_detection/"
    output_file = os.path.join(output_dir, "hello.txt")

    # Ensure the directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Write the string to the file
    with open(output_file, "w") as f:
        f.write(string_to_save)

    print(f"String saved to {output_file}")

if __name__ == "__main__":
    main()