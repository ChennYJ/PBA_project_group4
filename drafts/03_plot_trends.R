# ===========================================================
# DRAFT - reference only. Do not run as-is.
# Written before the raw data were downloaded: file paths and
# column names do not match data/raw/ yet. The final version
# will live in R/.
# ===========================================================

# 03_plot_trends.R
# Input : data/clean/panel_daily.csv
# Output: figures/fig1_trends.png, figures/fig1b_gap.png

library(tidyverse)

panel <- read_csv("data/clean/panel_daily.csv", show_col_types = FALSE)
tpass_start <- ymd("2023-07-01")

# Monthly mean daily rate per county, then average counties within group
monthly <- panel |>
  mutate(month = floor_date(date, "month")) |>
  group_by(group, county, month) |>
  summarise(rate = mean(moto_crash_rate), .groups = "drop") |>
  group_by(group, month) |>
  summarise(rate = mean(rate), .groups = "drop")

dir.create("figures", showWarnings = FALSE)

# Fig 1: both groups over time
p1 <- ggplot(monthly, aes(month, rate, colour = group)) +
  geom_line(linewidth = 0.8) +
  geom_vline(xintercept = tpass_start, linetype = "dashed") +
  annotate("text", x = tpass_start, y = Inf, label = "TPASS launch",
           hjust = -0.1, vjust = 1.5, size = 3.5) +
  scale_colour_manual(values = c(control = "#7f7f7f", treatment = "#d62728"),
                      labels = c(control = "Taipei + New Taipei",
                                 treatment = "No prior pass (8 counties)")) +
  labs(x = NULL, y = "Motorcycle injury crashes\nper 100,000 residents per day",
       colour = NULL,
       title = "Motorcycle crash rates before and after TPASS") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top")

ggsave("figures/fig1_trends.png", p1, width = 8, height = 4.5, dpi = 300)

# Fig 1b: gap between groups (should be flat before July 2023)
gap <- monthly |>
  pivot_wider(names_from = group, values_from = rate) |>
  mutate(gap = treatment - control)

p2 <- ggplot(gap, aes(month, gap)) +
  geom_line(linewidth = 0.8) +
  geom_vline(xintercept = tpass_start, linetype = "dashed") +
  geom_hline(yintercept = mean(gap$gap[gap$month < tpass_start]),
             colour = "grey60") +
  labs(x = NULL, y = "Treatment minus control",
       title = "Gap in motorcycle crash rate (grey line = pre-TPASS mean)") +
  theme_minimal(base_size = 12)

ggsave("figures/fig1b_gap.png", p2, width = 8, height = 4, dpi = 300)

p1
p2
