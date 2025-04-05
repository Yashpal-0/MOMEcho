import tkinter as tk
import numpy as np
import random
import math

GRID_SIZE = 8
STATES = ['asleep', 'awake', 'cranky']
INDICATOR_COLORS = ['gray', 'lightblue', 'blue']

def get_indicator_intensity(state):
    return {'asleep': 0, 'awake': 1, 'cranky': 2}[state]

def generate_pressure_matrix(state):
    base_mask = np.zeros((GRID_SIZE, GRID_SIZE))
    base_mask[2:5, 3:5] = 1
    if state == 'asleep':
        pressure = np.random.normal(loc=80, scale=3, size=(GRID_SIZE, GRID_SIZE))
    elif state == 'awake':
        pressure = np.random.normal(loc=100, scale=10, size=(GRID_SIZE, GRID_SIZE))
    else:
        pressure = np.random.normal(loc=120, scale=30, size=(GRID_SIZE, GRID_SIZE))
    return (pressure * base_mask).clip(0, 255).astype(int)

class BabyMonitorGUI:
    def __init__(self, master):
        self.master = master
        master.title("MomEcho Baby Simulator")
        master.protocol("WM_DELETE_WINDOW", self.close)

        self.state_label = tk.Label(master, text="State: -", font=("Helvetica", 16))
        self.state_label.pack(pady=10)

        self.intensity_indicator_canvas = tk.Canvas(master, width=200, height=20)
        self.intensity_indicator_rect = self.intensity_indicator_canvas.create_rectangle(0, 0, 200, 20, fill='gray')
        self.intensity_indicator_canvas.pack(pady=5)

        self.cradle_canvas_width = 200
        self.cradle_canvas_height = 100
        cradle_body_width = 80
        cradle_body_height = 40
        stand_height = 15
        stand_width = cradle_body_width + 20
        total_cradle_height = cradle_body_height + stand_height

        self.initial_cx = self.cradle_canvas_width / 2
        self.initial_cy = self.cradle_canvas_height - total_cradle_height / 2 - 10
        self.current_cx = self.initial_cx

        basket_x1 = self.initial_cx - cradle_body_width / 2
        basket_y1 = self.initial_cy - total_cradle_height / 2
        basket_x2 = self.initial_cx + cradle_body_width / 2
        basket_y2 = basket_y1 + cradle_body_height

        stand_base_y = self.initial_cy + total_cradle_height / 2
        stand_top_y = stand_base_y - stand_height
        stand_left_x1 = self.initial_cx - stand_width / 2
        stand_left_x2 = self.initial_cx - cradle_body_width / 2
        stand_right_x1 = self.initial_cx + stand_width / 2
        stand_right_x2 = self.initial_cx + cradle_body_width / 2

        self.cradle_canvas = tk.Canvas(master, width=self.cradle_canvas_width, height=self.cradle_canvas_height, bg='lightyellow')

        self.cradle_canvas.create_arc(basket_x1, basket_y1, basket_x2, basket_y2 + 20, start=0, extent=180, style=tk.CHORD, fill='burlywood', outline='black', tags="cradle")
        self.cradle_canvas.create_arc(basket_x1, basket_y1, basket_x2, basket_y2 + 20, start=0, extent=-180, style=tk.ARC, outline='black', width=2, tags="cradle")

        self.cradle_canvas.create_line(stand_left_x1, stand_base_y, stand_left_x2, stand_top_y, width=3, fill='saddlebrown', tags="cradle")
        self.cradle_canvas.create_line(stand_right_x1, stand_base_y, stand_right_x2, stand_top_y, width=3, fill='saddlebrown', tags="cradle")
        self.cradle_canvas.create_line(stand_left_x2, stand_top_y, stand_right_x2, stand_top_y, width=3, fill='saddlebrown', tags="cradle")

        self.cradle_canvas.pack(pady=10)

        self.rocking_phase = 0.0
        self.target_amplitude = 0
        self.animation_job = None

        self.grid_frame = tk.Frame(master)
        self.grid_frame.pack()

        self.grid_labels = [[tk.Label(self.grid_frame, width=4, height=2, relief="solid", bg="white")
                             for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
        for i in range(GRID_SIZE):
            for j in range(GRID_SIZE):
                self.grid_labels[i][j].grid(row=i, column=j)

        self.simulate_button = tk.Button(master, text="Simulate Next", command=self.simulate_step)
        self.simulate_button.pack(pady=20)

        self.auto = False
        self.toggle_auto_button = tk.Button(master, text="Auto: OFF", command=self.toggle_auto)
        self.toggle_auto_button.pack()

        self.master.after(1000, self.auto_simulate)
        self.animate_cradle()

    def simulate_step(self):
        state = random.choices(STATES, weights=[0.4, 0.3, 0.3])[0]
        intensity_index = get_indicator_intensity(state)
        matrix = generate_pressure_matrix(state)

        self.state_label.config(text=f"State: {state.upper()}")
        self.intensity_indicator_canvas.itemconfig(self.intensity_indicator_rect, fill=INDICATOR_COLORS[intensity_index])
        self.update_grid(matrix)

        if state == 'asleep':
            self.target_amplitude = 0
        elif state == 'awake':
            self.target_amplitude = 15
        else:
            self.target_amplitude = 35

    def update_grid(self, matrix):
        for i in range(GRID_SIZE):
            for j in range(GRID_SIZE):
                val = matrix[i][j]
                color = f'#{val:02x}{val:02x}{val:02x}'
                if val == 0:
                    color = 'white'
                self.grid_labels[i][j].config(bg=color)

    def toggle_auto(self):
        self.auto = not self.auto
        self.toggle_auto_button.config(text=f"Auto: {'ON' if self.auto else 'OFF'}")

    def auto_simulate(self):
        if self.auto:
            self.simulate_step()
        if hasattr(self, 'master') and self.master.winfo_exists():
            self.master.after(1000, self.auto_simulate)

    def animate_cradle(self):
        if not hasattr(self, 'master') or not self.master.winfo_exists():
            return

        target_cx = self.initial_cx + math.sin(self.rocking_phase) * self.target_amplitude

        dx = target_cx - self.current_cx

        self.cradle_canvas.move("cradle", dx, 0)

        self.current_cx = target_cx

        self.rocking_phase += 0.1

        self.animation_job = self.master.after(20, self.animate_cradle)

    def close(self):
        print("Closing application...")
        if self.animation_job:
            self.master.after_cancel(self.animation_job)
            self.animation_job = None
        if hasattr(self, 'master') and self.master.winfo_exists():
             self.master.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = BabyMonitorGUI(root)
    root.mainloop()
