# 03_plot_trends.R
# Milestone figure: motorcycle crash rates before and after TPASS
#
# Input : data/clean/panel_daily.csv   (made by 02_build_panel.R)
# Output: figures/fig1_trends.png      (main figure, 2 panels)
#         figures/table1_descriptives.csv
#
# What changed from drafts/03_plot_trends.R
#   1. Group rates are population-weighted (Kaohsiung counts more than Nantou),
#      instead of a simple average of the counties.
#   2. Each group is indexed to its own pre-TPASS mean = 100, so the two lines
#      start at the same height and we compare trends, not levels.
#   3. The Level-3 COVID alert (2021-05-19 to 2021-07-26) is shaded.
#   4. Panel B shows the gap, with its pre- and post-TPASS means.
#   5. A 2x2 descriptive table (a hand-calculated DiD) is saved as well.

library(tidyverse)
library(patchwork)

panel <- read_csv("data/clean/panel_daily.csv", show_col_types = FALSE)

tpass_start <- ymd("2023-07-01")
covid_start <- ymd("2021-05-19")
covid_end   <- ymd("2021-07-26")

col_treat   <- "#eb6834"   # orange: 8 counties with no prior pass
col_control <- "#2a78d6"   # blue: Taipei + New Taipei

dir.create("figures", showWarnings = FALSE)

# ---- 1. Monthly, population-weighted rate for each group ----------------
# rate = crashes in group / (population x days, summed over counties) * 100,000
# Population is constant within a month (it changes once a year).
monthly <- panel |>
  mutate(month = floor_date(date, "month")) |>
  group_by(group, county, month) |>
  summarise(crashes = sum(n_moto),
            pop     = first(pop),
            days    = n(),
            .groups = "drop") |>
  group_by(group, month) |>
  summarise(rate    = sum(crashes) / sum(pop * days) * 1e5,
            .groups = "drop") |>
  group_by(group) |>
  mutate(index = rate / mean(rate[month < tpass_start]) * 100) |>
  ungroup() |>
  mutate(group = factor(group, levels = c("treatment", "control"),
                        labels = c("No prior pass\n(8 counties)",
                                   "Taipei +\nNew Taipei")))

# ---- 2. Panel A: indexed trends ------------------------------------------
x_breaks <- seq(ymd("2021-01-01"), max(monthly$month), by = "6 months")
labels_end <- monthly |> filter(month == max(month))

p_trend <- ggplot(monthly, aes(month, index, colour = group)) +
  annotate("rect", xmin = covid_start, xmax = covid_end,
           ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.6) +
  annotate("text", x = covid_end + 10, y = Inf, label = "COVID Level-3 alert",
           hjust = 0, vjust = 1.6, size = 3, colour = "grey40") +
  geom_hline(yintercept = 100, colour = "grey75", linewidth = 0.3) +
  geom_vline(xintercept = tpass_start, linetype = "dashed", colour = "grey30") +
  annotate("text", x = tpass_start + 10, y = Inf, label = "TPASS launch\n(Jul 2023)",
           hjust = 0, vjust = 1.3, size = 3, colour = "grey20", lineheight = 0.9) +
  geom_line(linewidth = 0.8) +
  geom_text(data = labels_end, aes(label = group),
            hjust = 0, nudge_x = 15, size = 3.2, lineheight = 0.9,
            show.legend = FALSE) +
  scale_colour_manual(values = c(col_treat, col_control)) +
  scale_x_date(breaks = x_breaks, date_labels = "%Y-%m",
               expand = expansion(mult = c(0.01, 0.16))) +
  labs(x = NULL,
       y = "Crash rate index\n(pre-TPASS mean = 100)",
       colour = NULL,
       title = "A. Motorcycle injury crash rate, by group") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top",
        legend.justification = "left",
        panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 11))

# ---- 3. Panel B: gap between the groups ----------------------------------
gap <- monthly |>
  mutate(g = if_else(as.integer(group) == 1, "treat", "control")) |>
  select(g, month, index) |>
  pivot_wider(names_from = g, values_from = index) |>
  mutate(gap = treat - control,
         period = if_else(month < tpass_start, "pre", "post"))

gap_means <- gap |>
  group_by(period) |>
  summarise(mean_gap = mean(gap),
            from = min(month), to = max(month), .groups = "drop")

did_index <- gap_means$mean_gap[gap_means$period == "post"] -
             gap_means$mean_gap[gap_means$period == "pre"]

p_gap <- ggplot(gap, aes(month, gap)) +
  annotate("rect", xmin = covid_start, xmax = covid_end,
           ymin = -Inf, ymax = Inf, fill = "grey85", alpha = 0.6) +
  geom_hline(yintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_vline(xintercept = tpass_start, linetype = "dashed", colour = "grey30") +
  geom_line(linewidth = 0.7, colour = "grey25") +
  geom_segment(data = gap_means,
               aes(x = from, xend = to, y = mean_gap, yend = mean_gap),
               inherit.aes = FALSE, colour = "black", linewidth = 1.2) +
  annotate("text", x = max(gap$month) + 15, y = mean(gap_means$mean_gap),
           label = sprintf("Change in\nmean gap:\n%+.1f points", did_index),
           hjust = 0, size = 3.2, colour = "grey20", lineheight = 0.9) +
  scale_x_date(breaks = x_breaks, date_labels = "%Y-%m",
               expand = expansion(mult = c(0.01, 0.16))) +
  labs(x = NULL,
       y = "Treatment minus\ncontrol (index points)",
       title = "B. Gap between groups (thick line = mean before / after TPASS)") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 11))

fig1 <- p_trend / p_gap +
  plot_layout(heights = c(2, 1)) +
  plot_annotation(
    title = "Did motorcycle crashes fall more where TPASS was new?",
    caption = paste0(
      "Source: National Police Agency A2 crash records; Ministry of the Interior population.\n",
      "Monthly crashes involving at least one motorcycle per 100,000 residents per day, ",
      "population-weighted within each group."),
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.caption = element_text(hjust = 0, colour = "grey40", size = 8))
  )

ggsave("figures/fig1_trends.png", fig1, width = 9, height = 6.5, dpi = 300, bg = "white")

# ---- 4. Table 1: descriptive statistics (2x2 DiD by hand) ----------------
# Population-weighted mean daily rate per 100,000, by group and period
desc <- panel |>
  mutate(period = if_else(post == 1, "After", "Before")) |>
  group_by(group, period) |>
  summarise(
    county_days       = n(),
    total_crashes     = sum(n_moto),
    rate_all          = sum(n_moto)      / sum(pop) * 1e5,
    rate_rush         = sum(n_moto_rush) / sum(pop) * 1e5,
    sd_rate_all       = sd(moto_crash_rate),
    .groups = "drop") |>
  mutate(period = factor(period, levels = c("Before", "After"))) |>
  arrange(desc(group), period)

did_raw <- desc |>
  select(group, period, rate_all, rate_rush) |>
  pivot_wider(names_from = c(group, period), values_from = c(rate_all, rate_rush))

did_all  <- (did_raw$rate_all_treatment_After  - did_raw$rate_all_treatment_Before) -
            (did_raw$rate_all_control_After    - did_raw$rate_all_control_Before)
did_rush <- (did_raw$rate_rush_treatment_After - did_raw$rate_rush_treatment_Before) -
            (did_raw$rate_rush_control_After   - did_raw$rate_rush_control_Before)

print(desc, width = Inf)
cat(sprintf("\nRaw DiD, all hours : %+.4f crashes per 100,000 per day\n", did_all))
cat(sprintf("Raw DiD, rush hours: %+.4f crashes per 100,000 per day\n", did_rush))
cat(sprintf("Change in mean gap (index points, Panel B): %+.1f\n", did_index))

write_csv(desc, "figures/table1_descriptives.csv")
