ether = 1e18
user1_deposit = 100000000
user3_deposit = 30000000

user2_borrow = 2000
total_deposit = user1_deposit + user3_deposit

interst_rate = 1.001
# interst = 1.0000001388

block = 86400 * 1000 / 12
block_per_day = 7200

total_interest = user2_borrow * (pow(interst_rate, block / block_per_day) - 1)
# total_interest = 3432

print(total_interest)

user3_deposit += total_interest * user3_deposit / total_deposit
user1_deposit += total_interest * user1_deposit / total_deposit

print(f"user1_deposit: {user1_deposit:.10f}")
print(f"user3_deposit: {user3_deposit:.10f}")
