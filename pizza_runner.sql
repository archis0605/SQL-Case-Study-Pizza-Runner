-- A. Pizza Metrics

/* 1.	How many pizzas were ordered?*/
select count(*) as total_pizzas_ordered
from customer_orders;

/* 2.	How many unique customer orders were made?*/
select count(distinct customer_id) as total_customers
from customer_orders;

/* 3.	How many successful orders were delivered by each runner?*/
select runner_id, count(*) as successful_delivered
from runner_orders 
where cancellation is null
group by 1;

/* 4.	How many of each type of pizza was delivered?*/
select pizza_name, count(*) as pizza_delivered
from customer_orders c
left join pizza_names p using(pizza_id)
where order_id in (
					select order_id
					from pizza_runner.runner_orders 
					where cancellation is null)
group by 1;

/* 5.	How many Vegetarian and Meatlovers were ordered by each customer?*/
select customer_id, pizza_name, count(*) as pizza_ordered
from customer_orders c
join pizza_names p using(pizza_id)
group by 1,2 with rollup
having pizza_name is not null;

/* 6.	What was the maximum number of pizzas delivered in a single order?*/
with delivered as (
	select order_id, count(*) as pizza_delivered
	from customer_orders
	where order_id in (
						select order_id
						from pizza_runner.runner_orders 
						where cancellation is null)
	group by 1)
select max(pizza_delivered) as max_pizza_deliver
from delivered;

/* 7.	For each customer, how many delivered pizzas had at least 1 change and how many had no changes?*/
select customer_id, 
	sum(case when exclusions is null and extras is null then 1 end) as no_changes,
	sum(case when (exclusions is null and extras is not null) or 
				  (exclusions is not null and extras is null) or 
                  (exclusions is not null and extras is not null) then 1 end) as atleast_one_change
from customer_orders
where order_id in (
					select order_id
					from pizza_runner.runner_orders 
					where cancellation is null)
group by 1;

/* 8.	How many pizzas were delivered that had both exclusions and extras?*/
select sum(case when exclusions is not null and extras is not null then 1 end) as no_of_pizzas 
from customer_orders
where order_id in (
					select order_id
					from pizza_runner.runner_orders 
					where cancellation is null);

/* 9.	What was the total volume of pizzas ordered for each hour of the day?*/
select hour(order_time) as hour_of_day, count(*) as no_of_pizzas
from customer_orders
group by 1 order by 1;

/* 10.	What was the volume of orders for each day of the week?*/
select dayofweek(order_time) as day_num, dayname(order_time) as day_of_week, count(*) as no_of_pizzas
from customer_orders
group by 1,2 order by 1;


-- B. Runner and Customer Experience

/* 1.	How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)*/
select weekofyear(registration_date + interval 1 week) as week_num, count(*) as runners_signed
from runners
group by 1;

/* 2.	What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?*/
with avgtime as (
	select distinct r.order_id, r.runner_id, timestampdiff(minute, order_time, pickup_time) as minutes
	from runner_orders r
	inner join customer_orders c using(order_id)
	where cancellation is null)
select runner_id, round(avg(minutes)) as average_time_minutes
from avgtime
group by 1;

/* 3.	Is there any relationship between the number of pizzas and how long the order takes to prepare?*/
select pizza_count, round(avg(time_required)) as avg_time_required
from (select distinct r.order_id, timestampdiff(minute, order_time, pickup_time) as time_required, 
		count(*) over(partition by order_id) as pizza_count
	  from runner_orders r
	  inner join customer_orders c using(order_id)
	  where pickup_time is not null) as relation
group by 1;

/* 4.	What was the average distance travelled for each customer?*/
select customer_id, round(avg(distance),1) as avg_distance
from runner_orders r
join customer_orders c using(order_id)
where distance is not null
group by 1 order by 1;

/* 5.	What was the difference between the longest and shortest delivery times for all orders?*/
select max(duration) as longest_delivery_times, min(duration) as shortest_delivery_time,
		(max(duration) - min(duration)) as difference
from runner_orders;

/* 6.	What was the average speed for each runner for each delivery and do you notice any trend for these values?*/
with average as (
	select order_id, runner_id, round((distance * 60)/duration, 2) as speed_kmph
	from runner_orders
	where cancellation is null
    )
select *, round(avg(speed_kmph) over(partition by runner_id),2) as avg_speed
from average;

/* 7.	What is the successful delivery percentage for each runner?*/
with percentage as (
	select runner_id, sum(case when cancellation is null then 1 else 0 end) as successful_delivery,
		count(*) as total_order
	from runner_orders
	group by 1)
select runner_id, concat(round((successful_delivery*100/total_order),2)," %") as successful_delivery_prcnt
from percentage; 


-- C. Ingredient Optimisation
create view pizza_recipe_new as (
select r.pizza_id, trim(j.topping) as topping
from pizza_recipes r
join json_table(trim(replace(json_array(r.toppings), ',', '","')), '$[*]' columns (topping varchar(50) path '$')) as j);

create view customer_order_new as (
select c.order_id, c.customer_id, c.pizza_id, trim(j.exclusions) as exclusion,
		trim(k.extras) as extras, order_time
from customer_orders c
join json_table(trim(replace(json_array(c.exclusions), ',', '","')), '$[*]' columns (exclusions varchar(50) path '$')) as j
join json_table(trim(replace(json_array(c.extras), ',', '","')), '$[*]' columns (extras varchar(50) path '$')) as k);

/* 1.	What are the standard ingredients for each pizza?*/
select p2.pizza_name, group_concat(p3.topping_name separator ', ') as standard_ingredients
from pizza_recipe_new p1
inner join pizza_names p2 using(pizza_id)
inner join pizza_toppings p3 on p3.topping_id = p1.topping
group by 1;

/* 2.	What was the most commonly added extra?*/
select topping_name as most_commonly_added_extra
from pizza_toppings
where topping_id = (
					select extras
					from (
						select extras, count(*) as times_used
						from customer_order_new
						where extras is not null
						group by 1 order by 2 desc limit 1
						 ) 
					as t
				   );
                   
/* 3.	What was the most common exclusion?*/
select topping_name as most_common_exclusion
from pizza_toppings
where topping_id = (
					select exclusion
					from (
						select exclusion, count(*) as times_used
						from customer_order_new
						where exclusion is not null
						group by 1 order by 2 desc limit 1
						 ) 
					as t
				   );

/* 4.	Generate an order item for each record in the customers_orders table in the format of one of the following:
o	Meat Lovers
o	Meat Lovers - Exclude Beef
o	Meat Lovers - Extra Bacon
o	Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers*/
with generate_cust_order as (
	select distinct con.order_id, con.customer_id, con.pizza_id, 
		   concat("Exclude ",pt.topping_name) as exclusion, 
           con.extras, con.order_time
	from customer_order_new con
	left join pizza_toppings pt 
	on con.exclusion = pt.topping_id
)
select distinct gc.order_id, gc.customer_id, gc.pizza_id, 
	   gc.exclusion as exclusion, 
       concat("Extra ", pt.topping_name) as extras, gc.order_time
from generate_cust_order gc
left join pizza_toppings pt 
on gc.extras = pt.topping_id;

/* 5.	Generate an alphabetically ordered comma separated ingredient list for each pizza order 
from the customer_orders table and add a 2x in front of any relevant ingredients
o	For example: "Meat Lovers: 2xBacon, Beef, ... , Salami" */

/* 6.	What is the total quantity of each ingredient used in all delivered pizzas sorted by most frequent first?*/
with updation as (
	select distinct r.order_id, duration, c.pizza_id, 
	length(c.exclusions) - length(replace(c.exclusions, ',', '')) + 1 as total_exclusions, 
	length(c.extras) - length(replace(c.extras, ',', '')) + 1 as total_extras, 
	length(p.toppings) - length(replace(p.toppings, ',', '')) + 1 as total_toppings
	from runner_orders r
	join customer_orders c using(order_id)
	join pizza_recipes p on p.pizza_id = c.pizza_id
	where r.cancellation is null
	order by duration asc)
select order_id, pizza_id, total_exclusions, total_extras,
case when total_exclusions = total_extras then total_toppings
	 when total_exclusions is null and total_extras is null then total_toppings
	 when total_exclusions is null and total_extras >= 1 then (total_toppings + total_extras)
     else (total_toppings - total_exclusions)
     end as toppings_required
from updation;

-- D. Pricing and Ratings

/* 1.	If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes - 
how much money has Pizza Runner made so far if there are no delivery fees?*/
with total as (
	with pizza_details as (
		select *
		from runner_orders
		where cancellation is null)
	select distinct *, if(pizza_id = 1, 12, 10) as pizza_cost
	from pizza_details pd
	join customer_orders co using(order_id))
select runner_id, sum(pizza_cost) as total_earning
from total
group by 1;

/* 2.	What if there was an additional $1 charge for any pizza extras?
o	Add cheese is $1 extra */
with additional_details as (with pizza_details as (
		select *
		from runner_orders
		where cancellation is null)
	select distinct *, if(pizza_id = 1, 12, 10) as pizza_cost,
		case when co.extras is null then 0
			 else (length(co.extras) - length(replace(co.extras, ',', '')) + 1)
             end as additional_cost
	from pizza_details pd
	join customer_orders co using(order_id))
select runner_id, sum(pizza_cost+additional_cost) as total_cost
from additional_details
group by 1;

/* 3.	The Pizza Runner team now wants to add an additional ratings system that allows customers to rate their runner, 
how would you design an additional table for this new dataset - generate a schema for this new table and 
insert your own data for ratings for each successful customer order between 1 to 5.*/
create view runner_orders_new as (select *, if(cancellation is null, floor(1 + rand() * 5), null) as ratings
from runner_orders);

/* 4.	Using your newly generated table - can you join all of the information together 
to form a table which has the following information for successful deliveries?
o	customer_id
o	order_id
o	runner_id
o	rating
o	order_time
o	pickup_time
o	Time between order and pickup
o	Delivery duration
o	Average speed
o	Total number of pizzas*/
with cte as (select distinct con.customer_id, ron.order_id,
		ron.runner_id, ron.ratings, con.order_time,
        ron.pickup_time, concat(timestampdiff(minute, con.order_time, ron.pickup_time)," min") as time_diff_order_and_pickup,
        ron.duration as delivery_duration, round(ron.distance*60/ron.duration,1) as speed_kmph,
        count(*) over(partition by ron.order_id) as total_no_of_pizzas
from customer_order_new con
right join runner_orders_new ron using(order_id)
where cancellation is null)
select customer_id, order_id, runner_id, round(avg(ratings)) as ratings,
		order_time, pickup_time, time_diff_order_and_pickup,
        delivery_duration, speed_kmph, total_no_of_pizzas
from cte
group by 1,2,3,5,6,7,8,9,10;

/* 5.	If a Meat Lovers pizza was $12 and Vegetarian $10 fixed prices with no cost for extras and each runner 
is paid $0.30 per kilometre traveled - how much money does Pizza Runner have left over after these deliveries? */
with leftover as (
	with total as(
		select distinct c.order_id, r.runner_id, c.pizza_id, r.distance,
		if(c.pizza_id = 1, 12, 10) as pizza_price, (r.distance*0.30) as runner_paid 
		from customer_orders c
		join runner_orders r using(order_id)
		where cancellation is null)
	select runner_id, sum(pizza_price) as total_pizza_price, sum(runner_paid) as total_runner_paid
	from total
	group by 1)
select runner_id, concat("$ ",round(total_pizza_price - total_runner_paid, 2)) as left_over_money
from leftover;