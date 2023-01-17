// This program was built to work on an ARMv7 architecture with a ARMv7 DE1-Soc system.
//
// Lukas Laudrain.

//  PSEUDO-CODE (fetched from wikipedia)
//
//  1  function Dijkstra(Graph, source):
//  2      
//  3      for each vertex v in Graph.Vertices:
//  4          dist[v] ← INFINITY
//  5          prev[v] ← UNDEFINED
//  6          add v to Q
//  7      dist[source] ← 0
//  8      
//  9      while Q is not empty:
// 10          u ← vertex in Q with min dist[u]
// 11          remove u from Q
// 12          
// 13          for each neighbor v of u still in Q:
// 14              alt ← dist[u] + Graph.Edges(u, v)
// 15              if alt < dist[v]:
// 16                  dist[v] ← alt
// 17                  prev[v] ← u
// 18
// 19      return dist[], prev[]

// INFORMATIONS 
//
// 1. All indexes starts at 0.
//
// 2. Because memory addresses are 4-bytes, when using indexes, I often multiply these indexes by the 
//    value #4 so as to get the byte offset of the index.
//
// 3. The matrix used here is in the list data structure (because there are no matrix in asm).
//    e.g: So as to get the element at line 1 and column 3 (each starting at index 1) and
//         taking a matrix of size 4x4, we need to do 1*4+3=7, to get the element, we would need
//         to get the element at index 7 (for a list starting at index 1).
//   
//         [1,  2,  3,  4
//          5,  6,  7,  8,     <===> [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]
//          9,  10, 11, 12,
//          13, 14, 15, 16]
//
// 4. So as to get the path from a node to the source, you need to look at the values of the list stored
//    in the memory at the address stored in r1. If the value is 0xffffffff that means, there are no
//    previous value. The values represent the indexes of the previous nodes.

.equ el_count, 4

.global _start
_start:	
	// Initialisation
	//
	// R12 {word}             - The amount of nodes in the matrix 
	//
	// R0 {Array<el_count^2>} - Matrix (list) containing the values of the edges of the matrix
	// R1 {Array<el_count>}   - List containing the index of the previous node 
	// R2 {Array<el_count>}   - List containing whether the node at index i is visited or not (1 for visited, 0 for not)
	// R4 {Array<el_count>}   - List containing the distance from the source node to each node

	ldr r2, =visited
	ldr r1, =prev
	ldr r4, =dist
	ldr r0, =matrix
	ldr r12, =el_count
	// RESERVED REGISTERS : R0, R2, R4, R12
	
	// Lines 3-6 are made in the .data section. The INFINITY and UNDEFINED values are
	// replaced with the value 0xFFFFFFFF. 
	
	// Set the distance of the source at 0
	// (Source node is 0 here / the first one)
	mov r3, #0
	str r3, [r4]

	b main_while

// line 9: while loop
main_while:
	// Retrieving u (vertex not visited with the min distance)
	// Are stored in R6 (resp. R8) the value (min dist / dist[u]) and the index of the node.
	//
	// line 10: u ← vertex in Q with min dist[u]
	bl get_u
	
	// Put the value 1 in the previous list at the index R8 (index of the min value).
	//
	// line 11: remove u from Q (set u as visited)
	mov r3, #4
	mul r3, r3, r8
	mov r5, #1
	str r5, [r2, r3]
	
	// These registers are used until the end of the "neighbors_loop" branch.
	// 
	//  R5 - The index counter for the neighbors (starting at 0)
	//  R9 - The amount of bytes to get the first element of the line
	//      (because the matrix is in an array) (the index of u * 4 * 4 / index if matrix is [[1, 2], [3, 4]])
	//                                                            ^   ^          
	//                               number of elements in the line   size of a word   
	//
	// R11 - The sum of the distance of the node plus the distance between this node and the neighbor
	//       (alt = dist[u] + dist_between(u, v))
	//
	//  R6 - dist[u]
	// R10 - dist[v]
	
	mov r5, #0
	
	mov r9, #16
	mul r9, r9, r8
	
	// line 13: for each neighbor of u still in Q (still not visited)
	bl neighbors_loop
	
	// line 9 (bis): if all the nodes are visited, exit
	mov r3, #0
	bl exit_if_all_visited
	
	b main_while


// line 13: for each neighbir if u still in Q (still not visited)
neighbors_loop:
	// CONDITION 1 : Loop counter
	cmp r5, r12
	beq bx_lr
	
	// CONDITION 2 : Go to next if neighbor is already visited
	mov r3, #4
	mul r3, r3, r5
	ldr r3, [r2, r3] // R3 - The value in the "visited" list of the node/neighbor
	cmp r3, #1
	addeq r5, r5, #1
	beq neighbors_loop
	
	// CONDITION 3 : Go to next if the neighbor is the node (u == v)
	cmp r5, r6
	addeq r5, r5, #1
	beq neighbors_loop
	
	push {r2} // Temporary store the weight of the edge into r2
	
	mov r3, #4
	mul r3, r5, r3
	add r3, r3, r9 // Get the amount of bytes until the start of the line + the amount of bytes to reach the element
	ldr r2, [r0, r3]
	
	// CONDITION 4 : Check if the neighbor is linked to the node (not if r2 == INFINITY/0xFFFFFFFF)
	ldr r3, =0xffffffff
	cmp r2, r3
	addeq r5, r5, #1
	popeq {r2} // Don't forget to pop R2.
	beq neighbors_loop
	
	// Store into R10 the value of the distance of the neighbor 
	mov r3, #4
	mul r3, r5, r3
	ldr r10, [r4, r3]
	
	// line 14: alt ← dist[u] + Graph.Edges(u, v)
	add r11, r2, r6
	
	mov r3, #4
	mul r3, r5, r3 // Get byte amount to reach to index (r5=index counter of neighbor)
	
	// line 15: if alt(r11) < dist[v](r10)
	cmp r11, r10
	strlo r11, [r4, r3] // line 16: dist[v] ← alt
	strlo r8, [r1, r3]  // prev[v] ← u
	
	pop {r2}
	
	// Increment the counter
	add r5, r5, #1
	
	b neighbors_loop

// line 10: u ← vertex in Q with min dist[u]
get_u:	
	// Store :
	// R5  - The counter for the unvisited nodes
	// R6  - The value of the minimum value 
	// R8  - The index of the minimum value
	// R10 - the corresponding value in the unvisited node list
	// R11 - The corresponding value in the dist list
	
	mov r5, #0
	ldr r10, [r2]
	ldr r11, [r4]
	
	// Store into r6, the min value, either the infinity either the value of the first node
	// (if this node is not visited)
	cmp r10, #0
	moveq r6, r11
	moveq r8, #0
	ldrne r6, =0xffffffff 
	
	// Increment the counter
	add r5, r5, #1
	
	// Store "lr" value before going in the branch
	push {lr}
	
	// Run the loop to gather the min value in the stack
	bl loop
	
	// Retrieving the "lr" value
	pop {lr}
	
	bx lr

loop:
	// CONDITION : Loop counter
	cmp r5, r12
	beq bx_lr
	
	mov r3, #4
	mul r3, r3, r5
	ldr r10, [r2, r3] // (r2=address of unvisited node list)
	
	// CONDITION 1 : The node has already been visited
	cmp r10, #1 // (r10, =visited)
	addeq r5, r5, #1
	beq loop
	
	// Load the dist value of the node into r11 (r4, =dist)
	mov r3, #4
	mul r3, r3, r5
	ldr r11, [r4, r3]
	
	// CONDITION : If the node is lower than the min value, 
	//             replace the value of the lower node its index
	cmp r11, r6 // (r6, =min value)
	ldrls r6, [r4, r3]
	movls r8, r5
	
	add r5, r5, #1
	b loop



exit_if_all_visited:
	// CONDITION : If the end of the list is reached, every node is visited / END OF THE ALGORITHM
	cmp r3, r12
	beq end
	
	mov r5, #4
	mul r5, r3, r5
	ldr r8, [r2, r5]
	
	// If the node value in the previous list is at 0 (meaning not visited) we go back to the algorithm
	cmp r8, #0
	beq bx_lr
	
	// Increment the counter
	add r3, r3, #1
	
	b exit_if_all_visited

bx_lr:
	bx lr
	

end:
	b end
	
.data
	matrix:
		.word 0,6,9,13, 6,0,0xffffffff,8, 9,0xffffffff,0,3, 13,8,3,0,
	
	visited:
		.word 0,0,0,0
		
	dist:
		.word 0xffffffff,0xffffffff,0xffffffff,0xffffffff
		
	prev:
		.word 0xffffffff,0xffffffff,0xffffffff,0xffffffff
