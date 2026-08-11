-- =====================================================================
-- Healthcare Staff Productivity & Shift Analysis
-- SQL Deliverable — MySQL (fresh build)
-- =====================================================================

-- =====================================================================
-- 0. SCHEMA SETUP
-- =====================================================================
CREATE DATABASE IF NOT EXISTS hospital_staffs;
USE hospital_staffs;

--  DROP TABLE IF EXISTS shifts;
--  DROP TABLE IF EXISTS staff;
--  DROP TABLE IF EXISTS department;
--  DROP TABLE IF EXISTS dates;
--  DROP TABLE IF EXISTS role_benchmark;

CREATE TABLE staff (
    staff_id        VARCHAR(10)  PRIMARY KEY,
    staff_name      VARCHAR(100),
    role            VARCHAR(20),
    experience_yrs  INT,
    contract_type   VARCHAR(20),
    hourly_rate     DECIMAL(10,2)
);


CREATE TABLE department (
    dept_id                    VARCHAR(10) PRIMARY KEY,
    dept_name                  VARCHAR(50),
    required_staff_per_shift   INT,
    criticality                VARCHAR(10)
);

CREATE TABLE dates (
    date_id       VARCHAR(15) PRIMARY KEY,
    full_date     DATE,
    day_of_week   VARCHAR(10),
    month         INT,
    quarter       INT,
    year          INT,
    is_weekend    BOOLEAN
);

CREATE TABLE role_benchmark (
    role                    VARCHAR(20) PRIMARY KEY,
    max_patients_per_shift  INT,
    standard_shift_hrs      INT,
    overtime_threshold_hrs  INT
);

CREATE TABLE shifts (
    shift_id            VARCHAR(10) PRIMARY KEY,
    staff_id            VARCHAR(10),
    dept_id             VARCHAR(10),
    date_id             VARCHAR(15),
    shift_date          DATE,
    shift_type          VARCHAR(10),
    hours_worked        DECIMAL(4,1),
    overtime_hrs         DECIMAL(4,1),
    patients_attended   INT,
    absent_flag         BOOLEAN,
    FOREIGN KEY (staff_id) REFERENCES staff(staff_id),
    FOREIGN KEY (dept_id) REFERENCES department(dept_id),
    FOREIGN KEY (date_id) REFERENCES dates (date_id)
);

-- =====================================================================
-- Load in this exact order
-- =====================================================================

select * from Staff;
select * from Shifts;
select * from Department;
select * from Dates;
select * from Role_benchmark;

-- ======================================================================
-- Count() Row 
-- ======================================================================

select 
(select count(*) from department) as department,
(select count(*) from Staff) as Staff,
(select count(*) from Dates) as dates,
(select count(*) from role_benchmark) as role_benchmark,
(select count(*) from Shifts) as Shifts;

-- ==========================================================================
--                      Business Questions
-- ==========================================================================

-- Q1. Which departments are consistently running understaffed — where actual staff on shift is lower than
-- the required number?

-- drop view if exists staffing_actual;

-- a: actual staff present per shift-instance
create view staffing_actual as
select
    d.dept_id,
    d.dept_name,
    s.shift_date,
    s.shift_type,
    d.required_staff_per_shift,
    count(*) as actual_staff
from shifts s
join department d on s.dept_id = d.dept_id
where s.absent_flag = 'False'
group by d.dept_id, d.dept_name, s.shift_date, 
s.shift_type, d.required_staff_per_shift;

-- b: staffing gap + understaffed flag
select
    dept_id,
    dept_name,
    shift_date,
    shift_type,
    required_staff_per_shift,
    actual_staff,
    (required_staff_per_shift - actual_staff) as staffing_gap,
    case when (required_staff_per_shift - actual_staff) > 0 
    then 1 
    else 0 
    end as understaffed
from staffing_actual;

-- c: department-level severity and volume (replaces raw % understaffed)
select
    dept_name,
    count(*) as total_shift_instances,
    sum(understaffed) as understaffed_instances,
    round(avg(staffing_gap), 1) as avg_staffing_gap,
    sum(staffing_gap) as total_staffing_deficit
from(
    select dept_id, dept_name, shift_date, shift_type, required_staff_per_shift, actual_staff,
           (required_staff_per_shift - actual_staff) as staffing_gap,
           case when (required_staff_per_shift - actual_staff) > 0 
           then 1 
           else 0 
           end as understaffed
    from staffing_actual
) t
group by dept_name
order by avg_staffing_gap desc;

-- =================================================================
-- Q2. Which staff members or roles are accumulating the most overtime hours?
-- =================================================================
-- a: Overtime by individual staff member

select
    st.staff_id,
    st.staff_name,
    st.role,
    st.contract_type,
    round(sum(sh.overtime_hrs), 1) as total_overtime_hrs,
    count(*) as shifts_worked,
    round(avg(sh.overtime_hrs), 2) as avg_overtime_per_shift
from shifts sh
join staff st on sh.staff_id = st.staff_id
group by st.staff_id, st.staff_name, st.role, st.contract_type
order by total_overtime_hrs desc
limit 10;

-- b: Same data, ranked by intensity instead (avg overtime per shift)
select
    st.staff_id,
    st.staff_name,
    st.role,
    st.contract_type,
    round(sum(sh.overtime_hrs), 1) as total_overtime_hrs,
    count(*) as shifts_worked,
    round(avg(sh.overtime_hrs), 2) as avg_overtime_per_shift
from shifts sh
join staff st 
on sh.staff_id = st.staff_id
group by st.staff_id, st.staff_name, st.role, st.contract_type
order by avg_overtime_per_shift desc
limit 10;

-- c: Role-level rollup
select
    st.role,
    round(sum(sh.overtime_hrs), 1) as total_overtime_hrs,
    round(avg(sh.overtime_hrs), 2) as avg_overtime_per_shift,
    count(distinct st.staff_id) as staff_count,
    round(sum(sh.overtime_hrs) / count(distinct st.staff_id), 2) as overtime_per_staff
from shifts sh
join staff st 
on sh.staff_id = st.staff_id
group by st.role
order by total_overtime_hrs desc;
-- ===========================================================================================
-- Q3. Which departments have the highest absenteeism rate, and on which days of the week does
-- absence peak?
-- ===========================================================================================

-- a: Absenteeism rate by department
select
    d.dept_name,
    count(*) as total_shifts,
    sum(case when sh.absent_flag = 'True' 
    then 1 
    else 
    0 end) as absent_shifts,
    round(sum(case when sh.absent_flag = 'True' 
    then 1 
    else 0 
    end) / count(*) * 100, 1) as absenteeism_rate_pct
from shifts sh
join department d on sh.dept_id = d.dept_id
group by d.dept_name
order by absenteeism_rate_pct desc;

-- b: Absenteeism by weekday — with correct Monday→Sunday order
select
    dt.day_of_week,
    case dt.day_of_week
        when 'Monday' then 1
        when 'Tuesday' then 2
        when 'Wednesday' then 3
        when 'Thursday' then 4
        when 'Friday' then 5
        when 'Saturday' then 6
        when 'Sunday' then 7
    end as day_of_week_num,
    count(*) as total_shifts,
    sum(case when sh.absent_flag = 'True' then 1 else 0 end) as absent_shifts,
    round(sum(case when sh.absent_flag = 'True' then 1 else 0 end) / count(*) * 100, 1) as absenteeism_rate_pct
from shifts sh
join dates dt on sh.date_id = dt.date_id
group by dt.day_of_week
order by day_of_week_num;

select absent_flag, count(*) 
from shifts 
group by absent_flag;

-- ==========================================================
-- Q4. How many patients is each staff member attending to per shift — and is this workload evenly
-- distributed?
-- ==========================================================

-- a: Workload per individual staff member
select
    st.staff_id,
    st.staff_name,
    st.role,
    sum(sh.patients_attended) as total_patients,
    count(*) as shifts_worked,
    round(avg(sh.patients_attended), 1) as avg_patients_per_shift
from shifts sh
join staff st on sh.staff_id = st.staff_id
group by st.staff_id, st.staff_name, st.role
order by avg_patients_per_shift desc
limit 10;

-- b: Evenness check — spread by role
select
    st.role,
    round(avg(sh.patients_attended), 1) as mean_patients,
    round(stddev(sh.patients_attended), 1) as std_patients,
    min(sh.patients_attended) as min_patients,
    max(sh.patients_attended) as max_patients
from shifts sh
join staff st on sh.staff_id = st.staff_id
group by st.role;

-- c-i: benchmark violations — shifts where patients_attended exceeded
-- the role's safe maximum (role_benchmark.max_patients_per_shift).
-- Joins staff -> shifts -> role_benchmark so each shift is compared
-- against the correct benchmark for that staff member's role.
select
    st.staff_name,
    st.role,
    sh.patients_attended,
    rb.max_patients_per_shift
from shifts sh
join staff st on sh.staff_id = st.staff_id
join role_benchmark rb on st.role = rb.role
where sh.patients_attended > rb.max_patients_per_shift;

-- c-ii (count): total number of shifts that breached the safe
-- patient-load benchmark, across all roles.
select count(*) as total_violations
from shifts sh
join staff st on sh.staff_id = st.staff_id
join role_benchmark rb on st.role = rb.role
where sh.patients_attended > rb.max_patients_per_shift;

-- =================================================================
-- Q5: Which shift type (Morning, Evening, Night) is the most understaffed and has the highest overtime?
-- =================================================================

-- a: staffing severity and volume by shift type
-- Reuses staffing_actual (already filtered to present staff only).
select
    shift_type,
    count(*) as total_shift_instances,
    round(avg(required_staff_per_shift - actual_staff), 1) as avg_staffing_gap,
    sum(required_staff_per_shift - actual_staff) as total_staffing_deficit
from staffing_actual
group by shift_type
order by avg_staffing_gap desc;

-- b: overtime volume and intensity by shift type
select
    sh.shift_type,
    round(sum(sh.overtime_hrs), 1) as total_overtime_hrs,
    round(avg(sh.overtime_hrs), 2) as avg_overtime_per_shift,
    count(*) as shifts_count
from shifts sh
group by sh.shift_type
order by avg_overtime_per_shift desc;

-- c-i: average patient workload by shift type
select
    shift_type,
    round(avg(patients_attended), 1) as avg_patients_per_shift
from shifts
group by shift_type
order by avg_patients_per_shift desc;

-- c-ii: contract type mix by shift type
select
    sh.shift_type,
    st.contract_type,
    count(*) as shift_count
from shifts sh
join staff st on sh.staff_id = st.staff_id
group by sh.shift_type, st.contract_type
order by sh.shift_type, st.contract_type;


-- ===================================================================
-- Q6:What is the total overtime cost incurred per department over the 12-month period?
-- ===================================================================

-- 6: total overtime cost per department
-- overtime_cost = overtime_hrs * hourly_rate, computed per shift then summed
select
    d.dept_name,
    round(sum(sh.overtime_hrs * st.hourly_rate), 0) as total_overtime_cost,
    round(sum(sh.overtime_hrs), 1) as total_overtime_hrs
from shifts sh
join staff st on sh.staff_id = st.staff_id
join department d on sh.dept_id = d.dept_id
group by d.dept_name
order by total_overtime_cost desc;

-- =======================================================
-- Q7:Are contract and part-time staff being relied upon to cover gaps that should be filled by full-time
-- employees? 
-- =======================================================

-- 7: what share of each department's shifts were covered by
-- Contract or Part-Time staff, vs Full-Time
select
    d.dept_name,
    sum(case when st.contract_type = 'Full-Time' then 1 else 0 end) as full_time,
    sum(case when st.contract_type = 'Contract' then 1 else 0 end) as contract,
    sum(case when st.contract_type = 'Part-Time' then 1 else 0 end) as part_time,
    count(*) as total,
    round(
        sum(case when st.contract_type in ('Contract','Part-Time') then 1 else 0 end)
        / count(*) * 100, 1
    ) as contract_pct
from shifts sh
join staff st on sh.staff_id = st.staff_id
join department d on sh.dept_id = d.dept_id
group by d.dept_name
order by contract_pct desc;

-- =====================================================
-- Q8:Build a combined department-summary view — same shape as dept_summary in Python
-- =====================================================

-- Step 8a: one row per department, every root-cause metric together
create view dept_summary as
select
    u.dept_name,
    u.avg_staffing_gap,
    u.total_staffing_deficit,
    a.absenteeism_rate_pct,
    c.total_overtime_cost,
    r.contract_pct,
    d.criticality
from (
    select dept_name,
        round(avg(staffing_gap), 1) as avg_staffing_gap,
        sum(staffing_gap) as total_staffing_deficit
    from (
        select dept_name, (required_staff_per_shift - actual_staff) as staffing_gap
        from staffing_actual
    ) t
    group by dept_name
) u
join (
    select d.dept_name,
        round(sum(case when sh.absent_flag = 'True' then 1 else 0 end) / count(*) * 100, 1) as absenteeism_rate_pct
    from shifts sh
    join department d on sh.dept_id = d.dept_id
    group by d.dept_name
) a on u.dept_name = a.dept_name
join (
    select d.dept_name,
        round(sum(sh.overtime_hrs * st.hourly_rate), 0) as total_overtime_cost
    from shifts sh
    join staff st on sh.staff_id = st.staff_id
    join department d on sh.dept_id = d.dept_id
    group by d.dept_name
) c on u.dept_name = c.dept_name
join (
    select d.dept_name,
        round(sum(case when st.contract_type in ('Contract','Part-Time') then 1 else 0 end) / count(*) * 100, 1) as contract_pct
    from shifts sh
    join staff st on sh.staff_id = st.staff_id
    join department d on sh.dept_id = d.dept_id
    group by d.dept_name
) r on u.dept_name = r.dept_name
join department d on u.dept_name = d.dept_name;

select * from dept_summary order by avg_staffing_gap desc;

-- Step 8b: average of each metric grouped by criticality
-- (Low = General_Ward only, n=1 — reported separately, not as a group trend)
select
    criticality,
    count(*) as n_departments,
    round(avg(avg_staffing_gap), 2) as avg_staffing_gap,
    round(avg(total_staffing_deficit), 2) as avg_total_deficit,
    round(avg(absenteeism_rate_pct), 2) as avg_absenteeism_pct,
    round(avg(total_overtime_cost), 2) as avg_overtime_cost,
    round(avg(contract_pct), 2) as avg_contract_pct
from dept_summary
group by criticality
order by avg_staffing_gap desc;

-- Step 8c: Pearson correlation between avg_staffing_gap and absenteeism_rate_pct
select
    (count(*) * sum(avg_staffing_gap * absenteeism_rate_pct) - sum(avg_staffing_gap) * sum(absenteeism_rate_pct))
    /
    sqrt(
        (count(*) * sum(avg_staffing_gap * avg_staffing_gap) - sum(avg_staffing_gap) * sum(avg_staffing_gap))
        *
        (count(*) * sum(absenteeism_rate_pct * absenteeism_rate_pct) - sum(absenteeism_rate_pct) * sum(absenteeism_rate_pct))
    ) as correlation_gap_vs_absenteeism
from dept_summary;

-- Staffing gap vs. overtime cost (expecting ≈0.06):
select
    (count(*) * sum(avg_staffing_gap * total_overtime_cost) - sum(avg_staffing_gap) * sum(total_overtime_cost))
    /
    sqrt(
        (count(*) * sum(avg_staffing_gap * avg_staffing_gap) - sum(avg_staffing_gap) * sum(avg_staffing_gap))
        *
        (count(*) * sum(total_overtime_cost * total_overtime_cost) - sum(total_overtime_cost) * sum(total_overtime_cost))
    ) as correlation_gap_vs_overtime_cost
from dept_summary;

-- Staffing gap vs. contract % (expecting ≈0.07):
select
    (count(*) * sum(avg_staffing_gap * contract_pct) - sum(avg_staffing_gap) * sum(contract_pct))
    /
    sqrt(
        (count(*) * sum(avg_staffing_gap * avg_staffing_gap) - sum(avg_staffing_gap) * sum(avg_staffing_gap))
        *
        (count(*) * sum(contract_pct * contract_pct) - sum(contract_pct) * sum(contract_pct))
    ) as correlation_gap_vs_contract_pct
from dept_summary;

-- Highest Overtime Staff
SELECT s.staff_name, s.role, SUM(f.overtime_hrs) AS total_overtime_hrs
FROM shifts f
JOIN staff s ON f.staff_id = s.staff_id
GROUP BY s.staff_id, s.staff_name, s.role
ORDER BY total_overtime_hrs DESC
LIMIT 1;

-- Highest Absenteeism Staff
SELECT s.staff_name, s.role, COUNT(*) AS absent_count
FROM shifts f
JOIN staff s ON f.staff_id = s.staff_id
WHERE f.absent_flag = TRUE
GROUP BY s.staff_id, s.staff_name, s.role
ORDER BY absent_count DESC
LIMIT 1;

-- Highest Workload Staff
SELECT s.staff_name, s.role, AVG(f.patients_attended) AS avg_patients_per_shift
FROM shifts f
JOIN staff s ON f.staff_id = s.staff_id
GROUP BY s.staff_id, s.staff_name, s.role
ORDER BY avg_patients_per_shift DESC
LIMIT 1;

SELECT 
    s.role,
    COUNT(*) AS total_shifts,
    SUM(CASE WHEN f.absent_flag = TRUE THEN 1 ELSE 0 END) AS absent_shifts,
    ROUND(SUM(CASE WHEN f.absent_flag = TRUE THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS absenteeism_rate_pct
FROM shifts f
JOIN staff s ON f.staff_id = s.staff_id
GROUP BY s.role
ORDER BY absenteeism_rate_pct DESC;